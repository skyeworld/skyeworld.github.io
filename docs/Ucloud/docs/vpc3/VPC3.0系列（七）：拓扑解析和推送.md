# VPC3.0系列（七）：拓扑解析和推送

<p align="right"><font color=Grey>try.chen 2020-06-19</font></p>

## 名词定义

在  [对象模型](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%89%EF%BC%89%EF%BC%9A%E5%AF%B9%E8%B1%A1%E6%A8%A1%E5%9E%8B?id=vpc30%e7%b3%bb%e5%88%97%ef%bc%88%e4%b8%89%ef%bc%89%ef%bc%9a%e5%af%b9%e8%b1%a1%e6%a8%a1%e5%9e%8b) 中我们曾经提到我们通过对象间的引用关系来定义整个拓扑，我们先来定义几个名词：

| 名词   | 含义                                                                                                                   |
| ---- | -------------------------------------------------------------------------------------------------------------------- |
| 连通域  | 我们定义连通域为一个vm其所能通信的对端vm的最大集合。如VPC是一个连通域，两个打通的VPC共同组成一个连通域等。                                                           |
| 拓扑   | 由全部**相关的**BridgeObject对象按照引用关系组成的DAG，我们称为一个拓扑。举个例子来说，一个拓扑即为一个连通域所需的全部BridgeObject对象组成的集合，如每个VPC会形成一个拓扑，不通拓扑之间互相没有关联。 |
| 拓扑定义 | 在前文中我们提到，我们通过对象间引用关系来组织和定义拓扑，如 own/user/include。                                                                     |
| 拓扑解析 | 给定某个BridgeObject对象，寻找出其拓扑中的所有对象的过程我们称为拓扑解析。                                                                          |

## 拓扑定义

如[对象模型](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%89%EF%BC%89%EF%BC%9A%E5%AF%B9%E8%B1%A1%E6%A8%A1%E5%9E%8B?id=vpc30%e7%b3%bb%e5%88%97%ef%bc%88%e4%b8%89%ef%bc%89%ef%bc%9a%e5%af%b9%e8%b1%a1%e6%a8%a1%e5%9e%8b)中所述，我们定义了 own/use/include三种关系。因此对于一个VPC拓扑，我们实际通过如下图定义了整个拓扑：

<img title="" src="media/vpc3-10-2.png" alt="" data-align="center">

可以看到图中黄色区域即是我们通过引用关系定义的拓扑，创建、删除资源时会设置相应的ownr/user/include来引用相应的对象，并将自己嵌入整个拓扑中。对于网络对象来说，几乎所有的资源都会依附于VPC或者子网，因此VPC和子网是构建整个拓扑的关键，但除VPC和子网这两个业务对象之外，还有另外两种内部对象也会用于拓扑定义：global对象和vswitch对象。

### Global对象

我们定义了Global对象作为一个地域的根对象，所有继承与Global对象的资源都会被DPMgr推送到这个地域所有的所有的DPAgent和OpenVSwitch上。

我们通过定义Global对象用于推送一些全局性的、预埋性的flow对象，比如默认去往广播集群的flow、pipeline flow等等，这些对象和VPC、子网等业务对象没有必然联系。

Global对象的管理是由DPMgr上线时会创建一个内容空的Global对象，并持久化在resource-service中。该Global对象并无任何实际flow，仅用作继承，当某一对象需要被推送至全网时，仅需要将其owner设置为Global对象的id即可。

> Global对象的id总是初始化为该地域的regionId。

### vswitch对象

对于某些BridgeObject对象可能只向推给固定的ovs，如pipeline flow的灰度等，因此我们还定义了vswitch对象。当某些资源或者Flow想推送指定DPAgent、ovs时只需要将其owner设置为vswitch对象的id即可。

vswitch对象的创建是由DPAgent连接上DPMgr时，DPMgr会产生一个vswitch对象，vswitch对象的id总是初始化为这台ovs的dpid。

不过由于owner只能设置1个，如果一个对象已有其他owner，那么如何设置和vswitch对象的关联关系呢？我们可以借助于binding对象。只需要新建一个vswitch-binding（目前我们实际使用中称为pipeline-binding）对象，该vswitch-binding的owner即为vswitch对象，而include了其他需要下发对象即可。

**总结：** 可以看到从业务层面我们主要定义了VPC和子网两个对象来组织拓扑中的所有业务对象，而另外定义了Global和vswitch两个锚点对象用于内部推送策略控制。

## 拓扑解析

仍然在上图中，蓝色框图部分我们引入了`LocalInterface`对象，这是一个结合控制面和转发面的特殊对象，也是推送的关键所在。

在VPC3.0控制面中，会将每一个业务对象(Model)映射成对应的BridgeObject转发面对象，并根据Model的属性设置BridgeObject中的引用关系。那么最终生成的拓扑如何确定推送给哪些转发面（dpagent和ovs）呢？为此我们引入了`LocalInterface`对象。

当DPAgent捕获到vm的开机事件时后，会根据vm的mac地址本地生成关心的`LocalInterface`对象id，随即通过控制面拉取到该id对应的实际`LocalInterface`对象，而该对象有个关键引用：include了子网和VPC对象，于是DPMgr在昨晚拓扑解析之后，拉取到整个拓扑，并把拓扑下发给DPAgent，此后ovs获取到所有flow之后，连通性建立。

因此`LocalInterface`衔接了vm和拓扑之间的关系，控制面在生成拓扑对象时并不关心其被哪些转发面所使用，而是由转发面动态将vport注册到DPMgr上之后，进行拓扑解析之后下发整个拓扑。

那么我们所说的”拓扑解析“，具体是个怎样的流程呢？

```go
// 根据引用关系找到所有相关的对象
// 如根据localInterface对象的includes关系找到vpc和subnet，再根据vpc的owns关系找到vpc下所有的对象;
// 再根据Subnet对象的use关系找到routeTableBinding，根据binding的include关系找到routeTable对象.
func (c *ResourceCache) findRelated(ids []uint64, result map[uint64]*BridgeObject) error {
    unknown := map[uint64]bool{}

    for _, id := range ids {
        if _, ok := result[id]; ok {
            continue
        }
        // c.cache维护了id到BridgeObject的最新信息
        if obj, ok := c.cache[id]; ok {
            result[id] = obj
            for _, include := range obj.GetIncludes() {
                unknown[include] = false
            }
        } else {
            continue
        }
        // c.index维护了bridgeObject(key为id)到relations的映射关系
        if relations, ok := c.index[id]; ok {
            for own := range relations.Owns {
                unknown[own] = false
            }
            for use := range relations.Uses {
                unknown[use] = false
            }
        }
    }
    if 0 == len(unknown) {
        return nil
    } else {
        keys := make([]uint64, 0, len(unknown))
        for k := range unknown {
            keys = append(keys, k)
        }
        return c.findRelated(keys, result)
    }
}
```

可以看到拓扑解析，就是根据任意给定的对象，来查找所有相关联的对象，并返回最终的整个拓扑中的所有节点。

### 对象推送

DPMgr在推送更新时，首先会根据变更的对象进行拓扑解析，拿到拓扑结构之后，广播给所有注册的vswitch(dpagent)，因此此处存在”惊群“的情况，每个vswitch都会被唤醒，再遍历拓扑结构判断是否是自己感兴趣的变更。

如果某个变更vswitch认为自己感兴趣，则会将拓扑结构与vswitch当前的所有对象进行比较，并将diff结果发送给dpagent，用以更新转发面。

因此，如何高效的进行"vswitch是否感兴趣"判定，优化惊群问题，是后续的一个改进点。

### ovs版本亲和性

由于ovs在2.3/2.6/2.10等版本中对于flow的支持能力并不相同，因此在对象推送的过程中我们增加了ovs的版本亲和性。DPMgr再推送时会判断BridgeObject对象中的`OvsVersionAffinity`是否设置，如果设置则会比较对象ovs亲和性和vswitch(ovs)的版本是否匹配，以此进行一层过滤。

开发ovs版本亲和性的初衷主要是为了解决ovs2.3对于寄存器的支持较少，因此ovs 2.3和2.6的pipeline flow略有区别，包括ovs 2.6才支持ipv6等。

### relation解析

除了我们前文提到的基于对象引用关系的**标准**拓扑解析之外，DPMgr支持另一种**混杂模式**的拓扑解析：对于收到的任何对象变更都认为与自己是相关的。这个功能是由dpagent注册到dpmgr上时的type来决定。

混杂模式主要是为了支持诸如**rgw**之类的网关网元，因为网关网元本身是不含有任何interface的，但他仍然需要全网的转发BridgeObject对象，因此通过混杂模式来接受所有对象和变更。

### 安全性

由于DPMgr内存中维护着该地域的全量BridgeObject对象，也即全量flow，因此如何保证极端情况下的内存数据丢失之后，不影响转发面或者将对转发面的影响降低到最小，是整个系统安全行的重中之重。

#### 全量更新保护

对于DPMgr来说，如果从resource-service收到了一个对象数量为空的全量更新，则始终认为此次更新是不合法的，以此避免异常情况（如redis被清空）下的数据安全。

对于UXR的最佳实践来说，其在代码中规定短时间内变更不能删除超过指定数量的对象，否则会触发熔断拒绝操作，然而这个数值的设定对于VPC3.0来说还是相对较难的。首先因为一次操作可能会在短时间带来大量变更，如一次滚动发布涉及4000个POD启停等；并且由于dpmgr和resource-service全量更新或者是对账采用的是分片发送的方式，因此较难衡量一次全量更新具体操作的对象数量。

#### 持久化内存数据和延时备份

dpmgr通过挂在持久化存储，并将内存中的数据落盘来保证极端情况下的数据安全和快速拉起。对于备份方式可以采用”延时备份“的方式，即始终保证最新的备份是经过验证、稳定运行N分钟之前的全量数据，于是对于极端情况下的服务降级，可以快速回滚到N分钟之前,以此给控制面做一次"时光倒退"。

对于这样的服务降级，是为了解决大规模的灾难性问题，如异常数据带来的批量panic、数据被意外清除、数据库出现严重不可用等，同时带来的问题就是丢失了最近N分钟的增量事件，对于服务降级这认为是可接受的。

目前dpmgr使用的是挂载PVC的方式实现共享存储，存储使用的是KUN基于UFS提供的SSD存储，其提供的读写测试性能为：380M/s，无法提供最初提出的本地nvme SSD共享存储的方案。

<img title="" src="media/vpc3-7-n2.png" alt="" data-align="center">

目前对于dpmgr有三种集群角色：

| 集群  | 角色   | 读写PVC | 接受rs全量和增量 | 接受dpagent请求 | 作用                                          |
| --- | ---- | ----- | --------- | ----------- | ------------------------------------------- |
| s0  | 备份集群 | 写     | ✅         | ❌           | 仅用作备份，周期性将内存全量数据备份到PVC中。                    |
| s1  | 正常集群 | 读     | ✅         | ✅           | 正常提供服务，启动时会从PVC中读取出全量信息。                    |
| s9  | 延时集群 | 读     | ❌         | 仅在手动开启后会    | 冷备集群，出现极端灾难时，会切换到该冷备延时集群，用于提供极端情况下的服务恢复和保护。 |

##### 关于IO性能

由于UFS受限于网络传输带宽，导致速度较慢（380M/s），对于我们关心的读性能（备份可以后台异步备份，读取时需要快速启动）无法提供较好的保证。但KUN面临的难问题主要是受限于ceph集群的维护，以及无法提供基于本地盘ssd的共享存储。

##### 关于正常集群读取PVC

S1也会挂载PVC，并从中读取是因为减小服务上线、扩容时多副本拉取全量对redis造成的冲击，否则以北京二为例，上线一个dpmgr副本会拉取全量数据（大约4G），会完全造成redis hang住并带来巨大压力。

##### 关于序列化

目前文件序列化采用的方式比较简单，是基于`ffjson`的json序列化，序列化性能较差，有待优化。目前2G测试数据的性能为：序列化 15s 写 5s 读 6s 反序列化 38s。

| 测试项  | 耗时  |
| ---- | --- |
| 序列化  | 15s |
| 反序列化 | 38s |
| 写文件  | 2s  |
| 读文件  | 6s  |

##### 关于文件完整性

由于基于json序列化，如果文件出现不完整，会导致序列化失败从而无法处理。

##### 关于数据读取原子性

`s0`备份时会先写入临时文件，而只有写成功才会rename文件，以此保证其他集群不会读取中间状态的文件。但在其他集群读取的过程中，`s0` 重命名文件是否存在影响仍然需要验证。

#### 延时集群

该方案灵感收到瞿峰解决UXR批量core dump问题中提出的方案的启发，对于dpmgr常态情况下建立冷备集群，该集群的数据总是落后于正常集群N分钟，对于出现极端灾难时，立刻触发正常集群的所有dpmgr下线，使得dpagent立刻切换到冷备的”延时集群“，具体效果和上文的延时备份类似，只是通过冷备的方式缩短了从备份文件恢复内存的启动时间。

延时集群目前通过上述`s9`集群来提供，目前尚无自动化切换的方案和手段。当出现极端故障时，需要切换路由规则中的默认集群来切换dpagent的流量，并通过管理接口`/backup`来关闭s0的备份功能（防止下一个周期将异常数据同步到延时集群）。由于s9内存中的数据是通过PVC来读取的，且s0的备份总是滞后的（配置约15分钟），因此当dpagent切换到s9后相当于恢复到15分钟前的快照集群。
