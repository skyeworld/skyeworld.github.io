# BigBrother控制面设计: draft

<p align="right"><font color=Grey>try.chen 2018-11-08</font></p>


## 设计目标

### 功能要求

1. 判断是否联通？（复杂度 ⭐️⭐️）
2. 是否检查tunnel_id？（复杂度 ⭐️⭐️⭐️）
3. 是否需要判断包丢在了哪里？（复杂度 ⭐️⭐️⭐️⭐️⭐️）

### 规模要求

单个task最大支持**10k**个节点fullmesh测试，即单个VPC最大支持**10k**台虚机，对应**5000w**条流，1**亿**次注包；

### 性能要求

3s内分析完1k节点的fullmesh测试，对应发包100w个，收包600w个；

## 具体设计

![-w1061](media/15434052512148/15434142160530.jpg)

### 数据结构设计

**task_uuid**

FE每次提交都会生成一个UUID，该UUID唯一标识一次测试请求和测试任务，用户通过该UUID查询测试结果，以下称为task_uuid。

**task_id**

task_id 为 **6bit** 无符号整数，用于标识一次测试任务。**该 task_id 会被作为前缀嵌入染色的 TCP SYN 包的 TCP sequence 字段，用于receiver根据镜像的数据包识别出属于哪个测试任务。**

task_id 保持自增，当task_id达到最大时，会自动从0开始。

**sequnce_id**

sequnce_id 用于标识每一个发出去的数据包，为 **27bit** 的无符号整数。**27bit 最大为1.34亿，用于支持1亿发包的规模设计目标。**

**identifier**

identifier 为32bit无符号整数，由以下两部分构成：

| Bit | 31 ~ 27 | 26 ~ 0      |
| --- | ------- | ----------- |
|     | task_id | sequence_id |

**其中，前缀 5bit 为task_id，后缀 27bit 为sequnce_id，组合起来为identifier**。

sender发包时，将会给每一个发出的TCP SYN包染色，其中源目port为11，tcp sequence即为identifier。

receiver收包时，如果是SYN包，则根据tcp sequence可以提取出identifier，如果是 RST 或者 ASK，**则根据 tcp acknowledgment number 提取出identifier**（identifier应为ack数值-1）。

**由于task_id 最大只支持 5bit，因此并发最大只支持32个测试任务**。

**总结**

每一个 task_uuid 在测试任务的生命周期内，唯一对应到一个 task_id。当测试任务结束后，task_id会被回收。

生成测试任务时，随机产生一个uuid，并分配到一个 task_id，记录task_uuid和task_id的对应关系。

task_uuid 也对应到pair的数组，pair为测试的源目。按照5000w pair来计算，pair按照(src_mac,dst_mac,96bit) 计算，则占据572MB内存。因此这个pair是记录还是分析程序自己从数据库取出并自己构建？

![-w513](media/15434052512148/15434139065234.jpg)

### sender

sender 从 MQ 取到的信息应为 tun_dst 和包的字符数组。sender只负责发包，因此应该足够简单，依靠 MQ 可以水平扩展。

### receiver

receiver 的逻辑也应该足够简单。按照50w pair计算，receiver集群将会受到 600w个探测包。

如果receiver只是单纯的将包结构化为信息，再写入内存KV数据库或者数据库，那么对数据库的性能是个挑战，意味着600w次写请求。

redis按照30w qps计算，则光写入redis就需要20s。

因此receiver可以先做一次汇总。汇总之后，向内存数据库publish结果，最后由master receiver 根据内存数据库汇聚之后，写入DB。

![-w862](media/15434052512148/15434147261235.jpg)

但是如果需要实现判断包丢在哪里，意味着每个pair的六个包都需要保存和记录，以供分析程序分析。

否则每个pair只需要记录一个累加值标记收到了多少个包即可。

如果需要检查tunnel_id 错误，则需要分析包中的gre key字段。

receiver 需要解析的字段主要有：

- identifier
- tun_key
- tun_src
- nw_src
- nw_dst
- tcp_flags
