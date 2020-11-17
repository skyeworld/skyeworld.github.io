# BigBrother设计方案v1：基于PacketOut的单边注包


<p align="right"><font color=Grey>try.chen 2018-11-01</font></p>

## 概述

`BigBrother`是一套支持公有云、物理云、托管云的主动监控系统，通过发送icmp来收集点到点之间的连通性和时延情况。通过分析点到点之间的4次icmp报文镜像，可以快速准确判断出：

- 连通性是否正常
- 丢包丢在何处
- 时延是多少

## 设计概述

BigBrother的设计中主要考虑因素为如何构造一个染色的icmp request，并且主机、OS无关的icmp reply中可以携带该染色信息。采集时，只要将染色的request、reply镜像至BigBrother即可。

经过初步研究，openflow不支持icmp的sequence和identity，因此无法基于icmp来识别BigBrother的流量。

### 协议选择：TCP

基于TCP的端口扫描可用来判断连通性是否正常。通过发送SYN到常见端口，收集ACK/RST回包来判断通信正常，并可通过五元组作为身份信息。然而通过对北京二的扫描，端口扫描的成功率并不令人满意。

实验中，以北京二的92460台在线uhost/udb/umem为例，共扫描了以下常见端口:
`22,3306,6379,80,8080,3389,443,1080,11211,7001,8081`

共收到ACK/RST响应60759，回复率约为`65.7%`

分布如下

```
     27 port=1080, flags=SA
     75 port=11211, flags=SA
    118 port=8081, flags=SA
    146 port=7001, flags=SA
    204 port=3389, flags=SA
    412 port=443, flags=SA
    576 port=8080, flags=SA
    956 port=6379, flags=SA
   1391 port=22, flags=RA
   1634 port=3306, flags=SA
   1905 port=80, flags=SA
   2059 port=22, flags=SA
   3258 port=8081, flags=RA
   3596 port=7001, flags=RA
   4046 port=11211, flags=RA
   4771 port=1080, flags=RA
   5065 port=443, flags=RA
   5364 port=6379, flags=RA
   5698 port=80, flags=RA
   5950 port=3389, flags=RA
   6365 port=8080, flags=RA
   7143 port=3306, flags=RA
```

且扫描过程中，有些客户对此敏感，发现并疑问了我们的扫描过程。

### 协议选择：ICMP

基于`TCP/UDP`的扫描存在回复率不高、客户敏感等问题，因此目光再次回到ICMP。准备基于**IPv4** Header中的**dscp**或者**ttl**作为染色信息，通过ovs的**learn** action为反向的身份过滤提供基础。

通过learn，基本可以过滤绝大部分自定义icmp流量，以减轻不必要的icmp流量镜像到BigBrother。

### 基本原理

约定`ttl=192`的icmp流量作为特殊的、BigBrother的监控报文。BigBrother通过PacketOut构造的带有特殊**ttl**的icmp request，发送至目标vm，目标vm通过ovs learn action学习到一条反向的、置位nw_ttl=192的回程flow，后续的icmp reply匹配到该flow后即染色成功。

### 注意点

对于公有云探测物理云，BigBrother需要从物理云发送 icmp request，公有云探测托管云亦是如此。因为只有公有云有learn action的能力。

### TTL的选择

TTL通常作为OS被动探测的依据之一，常见OS的默认TTL如下：

| Operating System (OS)            | IP Initial TTL |
| -------------------------------- | -------------- |
| Linux (kernel 2.4 and 2.6)       | 64             |
| Linux (kernel 4.1)               | 64             |
| Google's customized Linux        | 64             |
| FreeBSD                          | 64             |
| Windows XP                       | 128            |
| Windows 7, Vista and Server 2008 | 128            |
| Cisco Router (IOS 12.4)          | 255            |

更多TTL参见 [default ttl on os](https://subinsb.com/default-device-ttl-values/)

## 详细设计

### 报文交互和采集流程

整体数据包交互如下图所示：

<img src="media/15425186628107/15425186797645.jpg" title="" alt="-w586" data-align="center">

**1. BigBrother构造报文**

BigBrother构造带有ttl=192的icmp request数据包，在vmA所在宿主机上通过`Packet-Out` resubmit到相应的端口。

**2. vmA 镜像并发送icmp request**

步骤一中Packet-Out的request会匹配`table 1`中的如下flow:

```
cookie=0x20007,table=1,priority=40000,metadata=0x1,icmp,icmp_type=8,icmp_code=0,nw_ttl=192 actions=send_BB,learn(),set_field:0x31->metadata,resubmit(,0)
```

该flow中，正对染色的icmp request会镜像(对应途中数据流②)一份到BigBrother(send_BB)，并会进行学习(*learn*)，加入`table 31`，最后resubmit到`table 0`中，走正常的转发逻辑。

由于此处虽然会进行学习，但实际并未生效，因此暂不详述。在`table 0`之后，染色的icmp request会发送给对端，对应途中的数据流即为③。

**4. vmB 镜像icmp request**

此处的镜像逻辑同步骤2中类似，这里主要描述一下learn action。

对于**learn**的动作信息如下(伪flow)：

```
learn(table=31,idle_timeout=3,hard_timeout=10,priority=30000,icmp,icmp_type=0,icmp_code=0,nw_src=[],nw_dst=[] actions=set_field:192->nw_ttl,tun_id=[],tun_dst=[],output=[],resubmit(,100))
```

~~其中match中的nw_src和nw_dst通过交换数据包中的源目来获得，tun_id，tun_dst也可以通过数据包中的gre header获得。~~ 最后resubmit到`table 100`中进行转发。

> 注：tun_id的源目端可能不同，不能通过使用request中的tun_id作为reply中的tun_id。

修改后的learn flow如下：

```
learn(table=31,idle_timeout=3,hard_timeout=10,priority=30000,icmp,icmp_type=0,icmp_code=0,nw_src=[],nw_dst=[] actions=set_field:192->nw_ttl,send_BB,set_field:0x32->metadata,resubmit(,0))
```

先进行染色，再镜像到BigBrother，并resubmit到`table_0`中，进行正常的转发逻辑。

> `table_31`的default动作是resubmit回`table_0`。
> `learning` 中不支持resubmit动作，resubmit的逻辑只能放在外层

**5. vmB镜像icmp reply**

vmB收到icmp request之后，一般情况下会回复icmp reply。该icmp reply会匹配`table_1`中的高优先级flow:

```
cookie=0x20007,table=1,priority=40000,metadata=0x1,icmp,icmp_type=0,icmp_code=0 actions=set_field:0x31->metadata,resubmit(,31),set_field:0x32->metadata,resubmit(,0)
```

首先该icmp reply会被resubmit到`table_31`中(即之前通过learn构建的table)。在`table_31`中，会匹配(icmp_reply,nw_src,nw_dst)学习到的flow，匹配后会染色，并镜像reply到BigBrother，最后跳回`table_0`中。

在`table_0`中按照正常的转发逻辑处理。

这就如图中的第⑤、⑥数据流所示。

**7. vmA镜像icmp reply**

vmA上会匹配到步骤5中所述的flow，进入`table_31`，将该reply镜像至BigBrother，最后送到`table_0`中。

## 总结

> v1方案最终被废弃，成为头脑风暴中一颗遗珠。该方案非常简单，但同时也有非常大的硬伤：
> 
> - 依赖源端可以进行`PacketOut`来注入数据包，几乎要求探测的一段只能是公有云(OpenVSwtich)；
> 
> - 同时依赖TTL进行染色，这有非常大的不确定性和不稳定性；
> 
> - 并且依赖SSH进入宿主机执行`PacketOut`命令极大限制了探测的性能。
