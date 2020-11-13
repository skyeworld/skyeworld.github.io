# VPC3.0系列（六）：事件和版本

<p align="right"><font color=Grey>try.chen 2020-06-19</font></p>

> 在VPC3.0中一切变更都来源于事件，事件是变更的基础。

在VPC3.0中通过一个单独的`event-service`服务来提供事件的发布、版本的生成、对象版本的管理和查询等功能，因此如何保证event-service的可靠、不丢失事件是本文的重点。

对于`event-service`有如下约定，如果`event-service`有给业务方返回，则`event-service`会保证事件一定能被处理成功，如果`event-service`没有返回（如超时等），则有业务方自己通过重试保证。

## 可靠事件处理

### 业务模型及SLA

`event-service`的业务模型较为简单，会首先更新数据库，之后再发布到MQ中。

<img title="" src="media/vpc3-6-1.png" alt="" data-align="center">

而我们担心的是，

1. 如果DB或者MQ出现短暂性异常、或者网络丢包等问题，那么如何保证可靠；

2. event-service如果在运行时panic或者宕机，那么处理中的请求和事件就会丢失；

对于第一个问题，我们一般会在内存里加重试来解决DB/MQ这些外部系统出现临时问题时的可靠手段，而此时系统的SLA就由系统的单点也就是event-service来保证（如果重试中event-service自己宕机则这些事件也就会丢失），因此如果假设event-service/db/mq三者的SLA都是99%的话，那么整个系统的SLA就是99%，也即event-service自己的可用性。

### 状态机方案

<img src="media/vpc3-6-3.png" title="" alt="" data-align="center">

在最早设计的思路中，通过状态机方案保证事件的可靠写入。发起方在进行自身业务逻辑前需要 `Init` 事件，而在业务逻辑结束后需要 `Commit` 事件，但这套方案有如下几个问题：

- **业务倾入性大**：API实现中需要在业务逻辑前后倾入事件Init/Commit/Abort等逻辑；

- **事件阻塞业务**：事件发送失败时会导致API失败，业务上不可接受；

- **宁滥毋缺机制依赖下游实现：** 对于超时的事件会进行commit处理，这也就导致当下游消费一个timeout的DELETE事件时，不能直接认为真正删除，而是需要先向数据库确认一次。

### Envoy Mirror方案

另一个简单暴力但不可行的方案就是在 istio gateway(envoy)入口处，对于每一个发送事件的请求都镜像N份分别给不通的event-service来处理，在网络层面做到多副本，保证单个节点宕机不会影响事件的丢失，但同样这个方案只能停留在纸面，因为会导致事件的冗余处理，给整个系统的请求放大了N倍，折算到成本上来说是上升的，不够可行性。

<img src="media/vpc3-event-mirror.png" title="" alt="" data-align="center">

### 安全队列方案

event-service的实现依赖了基于redis的安全队列方案，对于processing的任务会保存在redis中，当event-service节点宕机时，正在处理的事件并不会丢失。

<img src="media/vpc3-6-4.png" title="" alt="" data-align="center">

如图所示，整个流程如下：

- 业务方调用event-service `Pub`接口发送事件，该接口是异步接口；

- event-service收到Pub调用时，会将event任务  `SET` 进入redis中，key格式为 `/event-service/s1/event-job-id`，而value即为event序列化后的string。同时会将`event-job-id` 通过`LPUSH`从队尾压入`todo_list`中；

- (分支)如果上述两步操作返回成功，则`Pub`接口返回成功，如果上述操作返回失败，则会将event任务放入内存队列中；

- 此外，有一个常驻task goroutine会执行`BRPOPLPUSH`命令，从`todo_list`的队首拿到`job-id`的同时，并将该`job-id`放入`processing_list`中。对于该命令的详细解释如下：
  
  > 用法：RPOPLPUSH source destination
  > 
  > 命令 [RPOPLPUSH](http://redisdoc.com/list/rpoplpush.html#rpoplpush) 在一个原子时间内，执行以下两个动作：
  > 
  > - 将列表 `source` 中的最后一个元素(尾元素)弹出，并返回给客户端;
  > 
  > - 将 `source` 弹出的元素插入到列表 `destination` ，作为 `destination` 列表的的头元素;
  > 
  > 而BRPOPLPUSH则是RPOPLPUSH的block版本。
  
  可以看到我们依赖的正是`BRPOPLPUSH`的这一原子特性，客户端从`todo_list`取到event任务的同时，该任务也被放入了`processing_list`。后续及时事件未处理完就panic了，事件任务仍然在`processing_list`中未丢失；

- 当该task goroutine拿到待处理任务时，会调用事件的回调函数(callback)来完成事件的DB持久化和MQ的发布等操作；

- 如果callback成功，则意味着事件处理成功，因此会调用`LREM`将事件任务从`processing_list`中移除；如果callback失败，则意味着事件处理失败，不做处理，事件消费结束；

- 此外，另有一个monitor goroutine会监控在`processing_list`上，对于长期处于该队列中超过一定时间的任务，我们就认为消费方已经崩溃失败了，因此该monitor goutine会将该处理失败的事件任务通过`LPUSH`再次压入`todo_list`的队尾端，成功后在`LREM`删除`processing_list`；

而在此前第三点存在另一分支：如果redis写入失败，则event-service会自动降级为使用内存队列的方式来完成事件的消费、重试等处理。

#### 超时任务处理

对于`processing_list`中发现的超时任务，会压入`todo_list`的队尾来滞后处理，这是基于如下考虑：这个事件很可能已经超时了，因此优先保证其他正常事件优先处理，对于该事件做降级处理。

这么做还有一个好处就是如果放于队首的话，当下游DB/MQ发生短暂中断时，大量失败的事件会持续占据`todo_list`的队首，以此造成所有正常事件的延后处理，可能会进一步引起雪崩，造成大量事件积压和超时。

#### Redis可用性保证

redis本身的高可用仍然使用了哨兵机制，但在主从切换时可能会造成数据的丢失和不一致，此外尽管开启了持久化，但在宕机重启之后同样面临数据丢失的风险。对于这个问题，我们有如下考虑：

- 由于redis总是异步复制的，因此数据丢失的可能性始终是存在的。可以通过redis配置`min-slaves-to-write`和`min-slaves-max-lag`来降低丢失的可能，但会导致主节点的服务降级和不可写入，详情可以参考[Replication](http://redisdoc.com/topic/replication.html)；

- redis持久化使用SSD盘，开启AOF和RDB持久化，对于`appendfsync`设置为`always`，保证每次写入都同步落盘保证数据安全性。这会影响性能，但由于事件写入频率并不高（不到100 ops），因此SSD+`always`是可以接受的；

#### 服务降级和恢复

当redis队列不可用时会降级为内存队列，但内存队列是相对不可靠的（我们写的程序比起redis更有可能panic），因此当event-service发现redis可用之后（连续的ping-pong监控）会将内存队列中的任务同步到redis中，优先使用redis队列。

#### 约定

对比此前状态机方案，对于事件的约定行为有改变。在安全队列方案中，对于业务方发布事件来说是较为轻松和无倾入的，而event-service会尽力保证事件的可靠处理。分界点在于，如果event-service给予response，则几乎会保证事件的可靠消费，而event-service未响应时，需要业务方重试直到event-service给予response。

#### SLA

在安全队列方案中，当DB/MQ出现问题时事件需要重试时，有两道保障，分别是redis和event-service内存队列，因此只有当redis和event-service同时出现问题时整个系统才会出现问题。因此采用安全队列方案的可用性可以打到99.99%（1 – (0.01 * 0.01）= 99.99%），相较于此前内存队列的方案可以提升100倍的可用性。

## 版本管理

event-service除了实现了事件的可靠处理之外，还实现了版本的管理，可以理解为event-service是一个版本中心，每一个通过event-service发布的事件都会打上全局唯一且单调递增的版本号。

### 事件持久化

event-service对于每一个发布的事件都会持久化到数据库`t_network_event`表中，并通过该表的自增主键id作为事件的版本号。该表维护了最近6个月的事件记录。

同时该表也为托管云网关（HCGW）、物理云网关（VPCGW）、CNAT2提供了事件机制，这些服务会watch在事件表中以此来发现增量更新。

对于事件表的详细设计请参考[事件表设计方案](http://doc.vpc.ucloudadmin.com/#/vpc2/%E4%BA%8B%E4%BB%B6%E8%A1%A8%E8%AE%BE%E8%AE%A1%E6%96%B9%E6%A1%88)。

### 对象版本

同时，event-service会在同一个事务中更新`t_network_event_versions`表，使用最新的版本号来更新对象。该表维护了每个object最新的对象。

在前文[VPC3.0系列（三）：对象模型](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%89%EF%BC%89%EF%BC%9A%E5%AF%B9%E8%B1%A1%E6%A8%A1%E5%9E%8B)中我们提到，每个定义的对象中都携带了版本信息。而该版本的源头正是此处事件的发布。一次事件发布，以为着该对象的一次变更，于是触发一次版本递增，并记录在`t_network_event_versions`表中。

后续构建Model.Interface, Model.VCP等对象时，对象中的版本信息都来自于对该表的查询。

## 事件定义

event-service定义了如下三个`Service`

```protobuf
service EventPubService {
    // 异步接口, 不支持response中返回版本号
    rpc Pub (PubEventRequest) returns (PubEventResponse);

    // 同步接口，支持response中返回版本号
    rpc BPub (BPubEventRequest) returns (BPubEventResponse);
}

service EventObjectService {
    rpc DescribeObjectVersion(DescribeObjectVersionRequest) returns (DescribeObjectVersionResponse);
}
```

其中对于绝大部分场景调用`EventPubService.Pub`异步接口来发布事件即可，如果希望获取此次事件的版本号，则只能调用`BPub`同步接口。

> `BPub`接口并不会走安全队列模型，这是个同步接口。

对于事件的定义如下：

```protobuf
message Event {
    uint64 id = 1;                  // 事件ID，t_network_event中的主键。发送事件时不需要填该字段。
    Class  class = 2;               // 事件类别，如Class_VPC。发送事件时需要填写。
    Action action = 3;              // 事件操作, 如CREATE。发送事件时需要填写。
    string object = 4;              // 事件对象。发送事件时需要填写，一般为资源ID。
    string objectType = 5;          // 事件对象类型。发送事件时需要填写，对象的细分类型，无则留空。如VPC分为默认VPC(type=0)，私有VPC(type=1)，自定义VPC（type=2)。
    string subnetId = 6;            // 事件对象所属子网。发送事件时需要填写，无则留空。
    string vpcId = 7;               // 事件对象所属VPC。发送事件时需要填写，无则留空。
    uint32 accountId = 8;           // 事件对象所属account。发送事件时需要填写，无则留空。
    string requestId = 9;           // 事件请求ID。发送事件时需要填写，该id后续将作为x-request-id贯穿整个推送周期。
    uint64 date = 10;               // 事件发生时间。发送事件时需要填写，默认则自动填充当前时间。

    // ---- 扩展信息，发送事件时无需填写 ----
    string type = 11;               // 事件对象类型
    google.protobuf.Any body = 12;  // 事件对象（protobuf定义，非自定义[]byte）
    map<string,string> spanContext = 13; // 事件的trace context，不关心忽略即可。
}
```

其中的扩展信息，单独解释一下：

| 字段          | 含义                                                                                                                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------ |
| body        | protobuf.Any抽象类型，用于存放该事件对应的对象信息，目前只有安全组使用到了该字段，会存放安全组对象信息。                                                               |
| spanContext | 引入该字段是希望事件在穿越MQ时仍然可以被opentracing捕捉到，因此此处手动把SpanContext序列化到事件的该字段，后文会详细介绍这点。但该字段的引入是把双刃剑，导致事件无法直接使用protobuf.Equal函数来比较对象。 |

## 事件订阅

event-service会将事件发布到`nats-mq`中，因此业务方可以watch在该MQ上来监听关心的事件。

event-service会将事件按照如下topic投递：

```python
topic = event.<class>.<action>.<object>
```

对于`nats`来说，其通配掩码需要注意，如:

```python
# 订阅所有事件:
topic = event.>

# 订阅VPC下所有事件:
topic = event.VPC.>
```

**各地域NATS连接信息：**

| 地域  | 域名                                                    | 用户名和密码 |
| --- | ----------------------------------------------------- | ------ |
| 广州  | nats-vpc3-client.prj-vnpd-vpc3.kunsvc.a2.uae:4222     | **     |
| 上海二 | nats-vpc3-client.prj-vnpd-vpc3.kunsvc.a3.uae:4222     | **     |
| 北京二 | nats-vpc3-client.prj-vnpd-vpc3.kunsvc.a1.uae:4222     | **     |
| 预发布 | nats-vpc3-client.prj-vnpd-vpc3-dev.kunsvc.a3.uae:4222 | **     |
