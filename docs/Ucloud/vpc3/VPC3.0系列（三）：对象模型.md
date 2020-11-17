# VPC3.0系列（三）：对象模型

<p align="right"><font color=Grey>try.chen 2020-07-02</font></p>

> VPC3.0有一套严密、复杂的对象模型定义，理解了VPC3.0的对象模型也就理解了VPC3.0推送的核心逻辑。

## 概述

对于[VPC3.0系列（二）：模块和分层](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%BA%8C%EF%BC%89%EF%BC%9A%E6%A8%A1%E5%9D%97%E5%92%8C%E5%88%86%E5%B1%82)中的开局分层架构图，其实也是对象模型的边界图：

![](media/vpc3-brief.png)

可以看到 

- 微服务层主要负责 **Model** 对象的管理，这个`Model`对象我们特指拥有完整定义的业务对象，如`VPC`、`Subnet`、`Interface`、`RouteTable`、`ACL`等，定义在[proto/model](https://git.ucloudadmin.com/vnpd/protos/tree/master/model)中，用于系统间调用、`UVPCFE`交互，和数据库存储等；

- 中间层主要负责 **Resource** 对象的管理，包括持久化缓存、路由、分片和灰度等等，由 `Model` 对象根据 `Protobuf Any`序列化后得到，将具体某一种`Model`抽象为一个通用的`Resource`，定义在[model/resource.proto](https://git.ucloudadmin.com/vnpd/protos/blob/master/model/resource.proto)中；

- 转发层主要负责 **BridgeObject** 对象的管理，该对象会维护转发面所需要的信息，如`Flow`、`Group`、`Meter`等，该对象是由 *转发面翻译层* 将`Model`对象翻译成转发面数据而得到，因此对于同一个`Model`每种翻译层翻译的`BridgeObject`可能并不相同；

> **注意：** `Model`、`Resource`、`Object`描述的是同一个业务对象在不同层的存在形式以及对象定义，是可以同时存在的。如 `VPC` 这个业务对象流经微服务层时，会封装为 `Model.VPC`，而当流经中间层时，会封装为 `Resource`，而流经转发层会封装为`BridgeObject`。

# 

<img src="media/vpc3-model-tr.png" title="" alt="" data-align="center">

## 通用定义

不论是`Model`、`Resource`、还是`BridgeObject`，都有一系列通用定义和属性，我们先梳理下这些通用属性。

| 属性      | 类型     | 含义                                                                                                |
| ------- | ------ | ------------------------------------------------------------------------------------------------- |
| id      | uint64 | 对象唯一索引，相同对象该字段唯一，用于标识具体对象。是对象处理的关键，只在后端有效。                                                        |
| uuid    | string | 对象唯一字符串索引，除`Interface`对象外一般是资源id，`Interface`对象为mac，和`id`字段一般唯一映射。一般用于`Model`对象及微服务层；              |
| version | uint64 | 对象对应版本，一般为全局唯一版本（由事件层`Event-Service`分配所得），保持递增。对于同一个事件产生的`Model`、`Resource`、`BridgeObject`版本是相同的。 |
| deleted | bool   | 标记对象是否删除。                                                                                         |
| account | uint32 | 标记对象属于哪一个account(accountId，即项目Id)。                                                                |

## Model对象

`Model`对象是业务层的对象定义，一般用于微服务之间的互相调用，以及和`UVPCFE`的交互，由微服务层的服务生成。除了含有上述通用字段外，还含有具体的业务信息，如`RouteTable`对象中含有路由规则等属性，常见`Model`对象定义如下：

<!-- tabs:start -->

#### **Interface**

**Protobuf 定义**

```protobuf
message Interface {
    uint64 id = 1;                  // 网卡对象id, 和转发面cookie唯一对应
    string uuid = 2;                // 可选，如果是弹性网卡，则为弹性网卡Id，对于非弹性网卡，暂为空
    string mac = 3;                 // 网卡mac
    repeated IPv4Address v4 = 4;     // 一个网卡可绑定0或多个IPv4地址
    repeated IPv6Address v6 = 5;     // 一个网卡可绑定0或多个IPv6地址
    string objectId = 6;            // 绑定对象Id
    ObjectType objectType = 7;      // 绑定对象类型
    string subnetId = 8;            // 网卡所属SubnetId
    string vpcId = 9;               // 网卡所属VPCId
    uint32 account = 10;            // 网卡所属AccountId
    uint64 dpid = 11;               // 网卡对应的datapathId
    uint32 port = 12;               // 网卡对应datapath port
    uint64 vni = 13;                // 网卡所在的vpc对应的vni
    bool gray = 14;                 // 是否灰度到vpc3.0
    bool deleted = 15;
    Version version = 20;           // 网卡对象Version
    string eventId = 30;            // 对象最新变更的事件ID
}
```

#### **Subnet**

**Protobuf 定义**

```protobuf
message Subnet {
    uint64 id = 1;                      // 子网对象Id，和转发面cookie唯一对应
    string uuid = 2;                    // 子网资源ID
    string vpcId = 3;                   // 子网所属VPCId
    uint32 account = 4;                 // 子网所属AccountId
    int32 type = 5;                     // 子网类型，区分是否为基础子网
    string cidrBlockV4 = 6;             // 子网关联ipv4地址空间
    string gatewayV4 = 7;               // 子网对应的ipv4网关
    string cidrBlockV6 = 8;             // 子网关联ipv6地址空间
    string gatewayV6 = 9;               // 子网对应ipv6网关
    string routeTableId = 10;           // 子网关联的路由表Id
    bool deleted = 11;
    Version version = 20;               // 子网对象对应版本
    string eventId = 30;                // 对象最新变更的事件ID
}
```

#### **VPC**

**Protobuf 定义**

```protobuf
message VPC {
    uint64 id = 1;                      // vpc对象Id，和转发面cookie唯一对应
    string uuid = 2;                    // vpc资源Id
    uint32 account = 3;                 // vpc所属accountId
    uint32 tunnelId = 4;                // vpc对应的隧道Id，用于overlay租户信息标识
    repeated string cidrBlocksV4 = 5;   // vpc可关联多个ipv4地址空间
    string cidrBlocksV6 = 6;            // vpc可关联一个ipv6地址空间
    int32 type = 7;                     // vpc类型，兼容VPC2.0对象模型，在VPC2.0中标识是否是托管云VPC
    IPv6OperatorName operatorName = 8;
    bool deleted = 9;
    Version version = 20;               // vpc版本
    string eventId = 30;                // 对象最新变更的事件ID
}
```

#### **VPC打通**

**Protobuf 定义**

```protobuf
message VPCShareConnection {
    uint64 id = 1;
    string uuid = 2;
    uint32 account = 3;
    bool deleted = 4;
    string srcVpcUUId = 10;
    uint64 srcVpcId = 11;
    map<uint64, uint32> dstVpcs = 20; // key: vpcId  value: tunnelId
    Version version = 30;
    string eventId = 31;
}
```

#### **RouteTable**

**Protobuf 定义**

```protobuf
// 转发面使用的路由表对象。
// 当该路由表是VPC主路由表时，rules中仅包含主路由表规则；当该路由表是自定义路由表(子网路由表)时，rules中包含主路由表规则+自定义路由表规则。
// 当该路由表是Region路由表时，路由规则仅包含region路由表规则。
message BackendRouteTable {
    uint64 id = 1;                                      // 路由表id
    string uuid = 2;                                    // 路由表uuid
    uint32 account = 4;
    bool deleted = 8;
    repeated RouteRule rules = 9;
    Version version = 20;
    string eventId = 21;
}
```

#### **IPv4**

**Protobuf 定义**

```protobuf
message PrivateVIP {
    uint64 id = 1;
    string uuid = 2;
    string ip = 3;
    string mac = 4;
    string subnetId = 5;
    string vpcId = 6;
    uint32 account = 7;
    uint64 vni = 8;

    bool deleted = 19;
    Version version = 20;
    string eventId = 30;            // 对象最新变更的事件ID
}
```

#### **IPv6**

**Protobuf 定义**

```protobuf
message IPv6Address {
    string eipID    = 1;
    string ipv6     = 2;
    string subnet   = 3;
    IPv6OperatorName operatorName = 4;
}
```

#### **Datapath**

**Protobuf 定义**

```protobuf
message Datapath {
    uint64 id = 1; // datapath对象id，与转发面cookie唯一对应，为t_ovs_info表中主键id
    uint64 dpid = 2; // dpid
    repeated string ipv4 = 3;
    repeated string ipv6 = 4;
    repeated OverlayType type = 5;   // 隧道封装协议
}
```

<!-- tabs:end -->

### id取值

对于`Interface`对象来说，`id`即为`mac`的整数形式，而其他对象`id`一般来源于数据库主键`id`。如`VPC`对象的`id`来源于`t_vnet_info`中的主键`id`，所以`id`的长度定义为`48bit`。

### 缓存

`Model`层对象会缓存在`Resource-Service`中，并通过`metadata`设置的`use-cache`字段标识是否接受缓存。对于非强一致场景会通过缓存的对象降低数据库负载，而缓存的对象通过事件更新保证最终一致性。

## Resource对象

`Resource`对象是包含了`Model`对象、`BridgeObject`对象的通用对象，该对象由`Resource-Service`的client生成，如`FlowService`、`Resource-Builder`。

举个例子来说，`vpc-123`会有`Model`定义`model-vpc-123`，以及对应的转发面翻译对象`BridgeObject`：`bridgeObject-vpc-123`，而这两个对象需要被`Resource-Service`持久化存储、路由时，无法直接将原生对象发送给`Resource-Service`处理（`Protobuf`是强类型定义），而需要先wrap成`Resource`对象再给`Resource-Service`处理。

`Resource`的定义如下：

```protobuf
message ResourceMetadata {
    string type      = 1;
    string uuid      = 2;
    uint64 id        = 3;
    Version version  = 4;
    bool   deleted   = 5;
    uint32 account   = 6;

    // 对象最新变更的事件ID
    string eventId   = 10;

    // 用于追踪对象的span上下文
    map<string,string> spanContext = 11;
}

message Resource {
    ResourceMetadata    meta      = 1;
    google.protobuf.Any body      = 2;
}
```

可以看到`Resource`对象基本由之前提到的通用属性构成，而将某个`Model`对象序列化为`Resource`对象需要使用`protobuf`提供的`ptypes.MarshalAny`，类似于如下代码：

```go
import "github.com/golang/protobuf/ptypes"

func BuildResource(m *model.VPC) (*model.Resource, error) {
        body, err := ptypes.MarshalAny(m)
        if err != nil {
                return nil, err
        }

        m := &model.ResourceMetadata{
                Type:    body.GetTypeUrl(), // Resource-Service会根据该字段判断类型
                Uuid:    o.GetUuid(),
                Id:      generateId(m),
                Version: o.GetVersion(),
                Deleted: o.GetDeleted(),
                Account: o.GetAccount(),
        }
        r := &model.Resource{
                Meta: m,
                Body: body,
        }
        return r, nil
}
```

可以看到基本是将`Model`的通用属性赋值到`ResourceMetadata`字段，除了有一点例外：`id`字段。

### id定义

我们前文提到,`bridgeObject-vpc-123`是由`model-vpc-123`生成的，所以这两个对象会有相似的通用属性(id和version)，为了在`Resource-Service`里区分同一个业务对象的不同层衍生品，需要定义不同的`id`前缀，因此`Resource`的`id`取值来源于：

```go
// 以下代码定义在 vnpd/protos/model/object_helper.go，可直接使用

// typ 由UniversalResourceType 定义, 4bit
// subTyp 随typ而异，目前有两种，分别是datapath.BridgeObjectType 和 model.ModelObjectType, 12bit
// id 标识唯一对象，48bit
func GenerateObjectId(typ UniversalResourceType, subTyp int32, id uint64) uint64 {
    return uint64(typ)<<60 | uint64(subTyp)<<48 | id
}
```

可以看到`新id`由`UniversalResourceType`、`SubType`、`原始id`组成。

#### UniversalResourceType

一共`64bit`的`id`字段划分了三个区域，第一个区域为`UniversalResourceType`，`4bit`宽，这部分定义如下：

```protobuf
// 4 bit width
enum UniversalResourceType {
    Reserved = 0;

    // 转发面根据model对象生成的bridge对象，包含转发面信息如flow等;
    BridgeObject = 1;

    // model对象，如interface/subnet/vpc等资源层面对象;
    ModelObject = 2;
}
```

目前只有上下游两种对象：`ModelObject`和`BridgeObject`,分别代表微服务层对象和转发层对象。

#### SubType

第二个区域为`SubType`，`12bit`宽，含义随`UniversalResourceType`有不同定义，目前定义如下：

<!-- tabs:start -->

#### **ModelObject**

当UniversalResourceType定义为ModelObject时，SubType取值如下：

**Protobuf 定义**

```protobuf
// 12 bit width
enum ModelObjectType {
    ObjectInvalid = 0;
    ObjectPipelines = 1;
    ObjectDataPaths = 2;
    ObjectPipelineBinding = 3;

    ObjectInterface = 6;
    ObjectSubNetwork = 7;
    ObjectVPC = 8;
    ObjectPrivateVIP = 9;

    ObjectACL = 12;
    ObjectACLBinding = 13;

    ObjectSecurityGroup = 14;
    ObjectSecurityGroupBinding = 15;

    ObjectVpcShareConnection = 16;
    ObjectSubnetShareConnection = 17;

    ObjectRouteTableBinding = 18;
    ObjectBackendRouteTable = 19;
}
```

#### **BridgeObject**

当UniversalResourceType定义为BridgeObject时，SubType取值如下：

**Protobuf 定义**

```protobuf
// 12 bit width
enum BridgeObjectType {
    Invalid = 0;
    Pipelines = 1;
    DataPaths = 2;
    PipelineBinding = 3;
    LocalDatapath = 4;
    LocalInterface = 5;
    Interface = 7;
    SubNetwork = 8;
    VPC = 9;

    RouteTableBinding = 11;

    ACL = 12;
    ACLBinding = 13;

    SecurityGroup = 14;
    SecurityGroupBinding = 15;
    SecurityGroupPipeline = 16;

    // VPC打通、项目打通关联关系
    VPCShareConnection = 17;
    SubnetShareConnection = 18;

    // deprecated
    RouteTableRegion = 20;
    // deprecated
    RouteTableVpc = 21;
    // deprecated
    RouteTableSubnet = 22;

    BackendRouteTable = 23;

    PrivateVIP = 24;

    // dpagent local
    AsInterface = 100;
    LocalBroadcast = 101;
}
```

<!-- tabs:end -->

`SubType`用于标识具体的对象类型信息，不过中间层、转发层一般不关心这部分信息（对象是哪一种）。

## BridgeObject对象

`BridgeObject`是承载转发面信息的对象，`BridgeObject`由`转发面翻译层`的服务生成，典型服务有`FlowService`。一般来说一个`Model`对象会映射成若干个`BridgeObject`对象，是业务对象在转发面的映射。

`BridgeObject`主要定义如下：

```protobuf
message BridgeObject {
    uint64 id = 1;                  // 前16位为BridgeObjectType
    uint64 version = 2;
    BridgeContent content = 3;
    repeated uint64 includes = 4;   // 包含关系，目前用于LocalInterface包含SubNetwork and VPC； Binding包含RouteTable、ACL、SecurityGroup等
    uint64 owner = 5;               // 拥有关系，目前用于Interfaces和VPC之间建立双向关联关系
    uint64 user = 6;                // 使用关系，目前用于Binding和LocalInterface、SubNetwork之间建立关联关系
    repeated uint64 excludes = 7;   // 互斥关系，目前用于全局PipelineBinding灰度
    string eventId   = 10;          // 对象最新变更的事件ID
    map<string,string> spanContext = 11; // 用于追踪对象的span上下文
}
```

典型的id生成方式如下：

```go
func GenerateBridgeObjectInterfaceId(mac string) uint64 {
    m, err := util.MacToUint64(mac)
    if err != nil {
        panic(err)
    }
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_Interface), m)
}

func GenerateBridgeObjectLocalInterfaceId(mac string) uint64 {
    m, err := util.MacToUint64(mac)
    if err != nil {
        panic(err)
    }
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_LocalInterface), m)
}

func GenerateBridgeObjectAsInterfaceId(mac string) uint64 {
    m, err := util.MacToUint64(mac)
    if err != nil {
        panic(err)
    }
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_AsInterface), m)
}

func GenerateBridgeObjectSubnetId(subId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_SubNetwork), subId)
}

func GenerateBridgeObjectVpcId(vpcId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_VPC), vpcId)
}

func GenerateBridgeObjectRouteTableBindingId(subId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_RouteTableBinding), subId)
}

func GenerateBridgeObjectRouteTableId(rtId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_BackendRouteTable), rtId)
}

func GenerateBridgeObjectVipId(vipId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_PrivateVIP), vipId)
}

func GenerateBridgeObjectLocalBroadcast(subId uint64) uint64 {
    return model.GenerateObjectId(model.UniversalResourceType_BridgeObject,
        int32(datapath.BridgeObjectType_LocalBroadcast), subId)
}
```

其中，最关键的字段为`includes`、`owner`、`user`，我们先从对象间引用关系开始说起。

## 对象间引用

### 版本级联

> 在设计控制面推送时，我们选择了基于端到端事件+全局版本号的方式来控制整个更新流程，我们先简单介绍几个前提约束：
> 
> - **事件触发**：转发面变更都是由事件触发的，控制面只有收到某个对象的事件变更后，才会进行处理；
> 
> - **版本保序处理**：每次事件都会造成该对象的版本递增，控制面&转发面增量更新时，都会校验该对象版本号是否为最新（事件版本号大于本地缓存已处理版本号），只有版本号新于自己才会处理；

于是，我们在早期设计的过程中遇到了如下问题：

!> **示例一：路由表变更**

为了推送子网绑定的路由表信息，我们在子网对象的struct定义中引入了一个字段：绑定的路由表ID，用于描述该子网绑定了哪个路由表。**那么如果子网A绑定了路由表B,路由表B的规则变更了,版本如何变更?**

可以明确的是路由表的版本会++，那么子网的版本是否需要++呢？其实是需要的，如果子网的版本不++，就没法触发子网对象更新，也就没法触发子网绑定的路由表更新。

!> **示例二：新建云主机**

VPC下新建了网卡（云主机），那么VPC的版本是否需要++？

其实也是需要的，因为如果VPC的版本不++，也就没法触发VPC更新，这样就没法感知VPC下有新建对象，没法更新flow并推送，因此该VPC下的所有interface变更都会导致VPC的版本递增。

!> **示例三：region路由变更**

region路由表变更了（region路由表是所有用户自定义路由表的父节点，其规则会被merge进用户自定义路由表），那么全网路由表的版本是否要++？甚至全部子网版本是否要++？其实也是需要的，自定义路由表的版本不递增就无法触发路由表的变更，同时子网版本也需要变更（同示例一所述）。

因此可以看到，底层的任何微小的扰动都会造成上层对象的版本递增，最终引起一场版本号的风暴。版本号变更中引入业务逻辑（包含、继承等）造成对象级联，这是不可接受、也不可维护的，最终会造成版本的“💥”。

为了解决这个问题，是我们引入**对象间引用关系**的关键之一。

### 拓扑定义

我们首先需要回答一个问题：

> 当一个vm刚开机时，对应该vm的`dpagent`如何知道拉取哪些对象并下发fow？

对于上帝视角来说应该是：

- 所属subnet对应的`BridgeObject`;

- 所属vpc对应的`BridgeObject`;

- 所属subnet/vpc对应的路由表的`BridgeObject`;

- 所属vpc下的其他Interface对应的`BridgeObject`;

- 所属vpc打通的其他vpc上述信息；

- 其他...

在[早期设计](http://doc.vpc.ucloudadmin.com/#/vpc3/vpc3.0%E8%AF%A6%E7%BB%86%E8%AE%BE%E8%AE%A1)中，FlowManager承担了推送的工作，可以在[工作流程](http://doc.vpc.ucloudadmin.com/#/vpc3/vpc3.0%E8%AF%A6%E7%BB%86%E8%AE%BE%E8%AE%A1?id=%e5%b7%a5%e4%bd%9c%e6%b5%81%e7%a8%8b-1)中看到有两个关键接口：`GetCookieByVPC`和`GetFlowByCookie`，控制面需要为每个VPC准备好所有的对象索引（Cookie，同时有些Cookie是映射到子网、Interface等），再由转发面（Agent）自己来根据索引拉取具体的flow。

因此对于上述问题（我们称为拓扑解析，寻找连通域内的所有对象节点），需要FlowManager在拓扑发生变化时（如创建、删除云主机，变更路由表或ACL等），更新好VPC和Cookie的映射关系并及时推送下去。那么这个状态信息的生成和维护是这个问题的关键，如何灵活的控制拓扑解析，使得对于以后新加一种资源类型（如interface绑定安全组，interface绑定FlowLog）时可以不修改代码；如何高效的生成索引列表，满足推送时的性能等是设计拓扑解析时就需要应对的问题。

在早期设计时，索引的建立是需要固定在代码实现中的（如根据VPC拉所有的子网、以及子网下的Interface、子网绑定的路由表、ACL、打通的VPC及其子域等等），因此无法满足灵活控制和上线的需求。

为了解决这个问题，也是我们引入**对象间引用关系**的原因之一。

所以，如何组织对象和对象间的关系，并且该关系如何被控制面(dpagent/dpmgr)所识别并解析，是高效推送的关键，因此我们定义了如下的引用模型。

### 引用模型

![](media/model-reference.png)

从图中可以看到，我们定义了两种 **“对象”**：

| 对象        | 含义                                                                          |
| --------- | --------------------------------------------------------------------------- |
| 资源对象      | 如VPC、Interface、路由表等原子对象。                                                    |
| Binding对象 | 绑定关系对象，用于描述多个资源对象之间的绑定关系，如子网绑定路由表，子网绑定ACL，Interface绑定安全组等，重点在于描述“**绑定关系**”。 |

> 之所以单独定义绑定对象，是为了解耦对象之间的绑定关系，使得一种对象变更不会影响其连接的对端对象，当绑定关系变化时，只需要变更这个绑定对象本身即可。举个例子,对于控制面来说,子网重新绑定路由表时,只要推送绑定关系,而无需推送路由表。当一个网元上的N个实例绑定到了同一个路由表时，那么路由表只需推送一次，而不是N次，而只需要推送N次绑定关系。

定义好对象后，我们定义了对象间的三种 **“关系”**：

| 关系      | 含义   | 示例                                                                                                                                                                                                                                                                                                    |
| ------- | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| own     | 拥有关系 | vpc own interface，vpc拥有很多interface，interface的owner是vpc。用于关联vpc和interface之间的关系，之所以将interface和vpc关联，是因为interface的通信域是VPC而不是子网。                                                                                                                                                                          |
| use     | 使用关系 | subnet use binding对象(如RouteTableBinding)，binding对象的user是subnet。                                                                                                                                                                                                                                       |
| include | 引用关系 | binding对象(如RouteTableBinding) include 具体的对象(如RouteTable)。                                                                                                                                                                                                                                             |
| exclude | 互斥关系 | 互斥关系用于在引用关系中排除某些对象，如：已经设为broadcast状态的pipeline（继承于[Global对象](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%83%EF%BC%89%EF%BC%9A%E6%8B%93%E6%89%91%E8%A7%A3%E6%9E%90%E5%92%8C%E6%8E%A8%E9%80%81?id=global%e5%af%b9%e8%b1%a1)）需要灰度时，可以新建一个pipeline binding并设置和前述对象的互斥关系。 |

可以看到，通过这套模型我们比较好的解决了前文提到的“版本级联”和“拓扑定义”的问题。

**版本级联**

对于前文我们提到的三个问题：

- **路由表变更：** 子网 use 路由表Binding，路由表Binding include了路由表，因此只需要路由表对象++，而无需将子网版本++，因为子网对象和路由表对象已经通过binding隔离了，彼此无需直接感知；

- **新建云主机：** VPC own interface，因此只需要interface的版本++，vpc的版本并不需要递增，这是因为interface设置了自己的owner是vpc，因此控制面在进行拓扑解析时（后文会解释如何进行查找&解析）会通过VPC发现新创建的interface，即使VPC的版本并没有递增；

- **region路由表变更：** 子网 use 路由表Binding，路由表Binding include了多个路由表，分别是region路由表、子网路由表。因此只需要region路由表的版本++即可，子网路由表、子网的版本都不需要递增。原理同样是通过拓扑解析完成变更的查找。

因此，变更的版本回归对象本身，无任何衍生的业务逻辑问题，通过引用模型解决了“版本风暴”的问题。

**拓扑定义**

拓扑的定义不再由`GetCookieByVPC`这样的代码逻辑固化在服务中，而是通过对象的引用关系定义，因此新加资源对象以及对象简的关系时，我们只需要设置 use/own/include/exclude字段即可定义出所需要的拓扑，满足灵活性的要求。

## 声明式对象

>  VPC3.0的更新参考了K8S的声明式API设计理念，每次更新都致力于达到终态，因此在处理丢失、乱序、合并、重试等复杂场景时提供了更为可靠的更新机制。

在前文中我们提到，控制面每次更新时，都依赖版本的递增，那么如果转发面（如DPAgent）在处理A对象的version=100变更时失败了，此时后续A对象的101，102，103变更到来是还能继续处理吗？如果100失败了，是否会永远block A对象的后续处理呢？

如果100是一个ADD，101是一个DEL，那么非block的话是否就导致了业务的不可预期？

如果选择使用命令式更新的方式，我们不得不考虑上述问题，当某个中间版本持续失败时，会block所有后续处理，并且往往可能需要人为接入手动修复才能恢复处理（如脏数据影响）。

因此，VPC3.0控制面在增量更新时，始终传递的是**整个对象**，而非对象的**一次变更**，这个是对象更新机制中的核心机制。除了中间版本失败block问题，声明式对象更新还有如下好处：

- 天然幂等，便于重试；

- 处理乱序、版本丢失时都非常简单，直接根据最新版本更新到终态即可，乱序且过时的可不做处理，版本丢失也无需关心；

- 对象折叠&合并，同一对象连续的N次变更同时到达某个服务时，该服务可以丢弃中间所有对象，直接选择最终对象（版本最大），通过折叠&合并，降低更新次数，提高性能；

同时，声明式更新也难以避免一个问题：更新时的性能问题。由于每次RPC都需要传递整个对象，对于某些大对象（如路由表）可能会浪费额外的网络IO、序列化反序列化耗时、转发面（OVS）原子更新耗时等。

## 版本号机制

如前文proto中定义，每一个对象的struct定义中都携带有版本号，而该版本号在数据变化源头就会被带上，并随着对象在系统中的流动贯穿其整个生命周期，关于版本号后文会详细介绍。

## BridgeObject对象引用关系

<!-- tabs:start -->

#### **Interface**

Interface对象的引用关系如下：

| 关系    | 值     | 含义                            |
| ----- | ----- | ----------------------------- |
| owner | vpcId | interface所属vpc的vpc id(uint64) |

> **解释：**  Interface对象会将owner设置为vpc，便于根据VPC寻找到其下所有的Interface对象。

#### **Local Interface**

Local Interface对象的引用关系如下：

| 关系      | 值               | 含义                                                |
| ------- | --------------- | ------------------------------------------------- |
| include | subnetId, vpcId | interface对象的所属的subnet id(uint64) 和 vpc id(uint64) |

> **解释：**  Local Interface对象会将include设置为所属的subnetId和vpcId。

#### **IPv6**

IPv6对象携带了IPv6相关的flow，并且由于ovs对于IPv6 Flow的支持限制（主要是userdata字段），IPv6对象设置了[OVS版本亲和性](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%83%EF%BC%89%EF%BC%9A%E6%8B%93%E6%89%91%E8%A7%A3%E6%9E%90%E5%92%8C%E6%8E%A8%E9%80%81?id=ovs%e7%89%88%e6%9c%ac%e4%ba%b2%e5%92%8c%e6%80%a7)，对于IPv6只有OVS 2.6及以后的版本才会推送该对象。

IPv6对象的引用关系如下：

| 关系    | 值           | 含义                      |
| ----- | ----------- | ----------------------- |
| owner | interfaceId | 该IPv6对象对应的Interface对象Id |

#### **Subnet**

Subnet对象不会设置owner、user、include。

#### **VPC**

VPC对象不会设置owner、user、include。

#### **RouteTableBinding**

**路由表对象设计**

我们把路由表绑定设计在子网上，这是因为路由表是可以关联到子网级别的，因此我们在include中包含的路由表其实是最终生效的子网路由表，其中的路由规则包含VPC主路由表中的路由规则，同时也包含子网路由表本身的路由规则；而region默认路由表的规则我们是嵌在子网路由表对象的include字段中的。

我们之所以把region路由表的路由规则和子网路由表的规则隔离开来，是因为以下两点：

- 同一台宿主机上的region默认路由表flow可以共享和复用，而不需要每个vm都推送一遍；
- region默认路由表变更时，只需要推送默认路由表即可，而无需全网子网路由表都推送一遍；

---

RouteTable对象的引用关系如下：

| 关系      | 值            | 含义                        |
| ------- | ------------ | ------------------------- |
| user    | subnetId     | 关联该binding对象的子网           |
| include | routeTableId | 该binding对象对应的路由表Id，有且只有一个 |

#### **RouteTable**

在这里多说一点RouteTable对象的设计，对于路由表中的路由规则有以下几种特殊情况：

- instance路由：对于instance路由，nexthopId会设置为instance所对应的ip；该instance如果发生迁移，那么路由表是不需要变化的，因为转发面会先找到instance路由，而后根据路由中设置的ip去找实际的mac和位置关系，而这个位置关系是由Interface对象来确定的；
- vip路由：对于vip路由，nexthopId会设置为vip所在的当前vip；在这里我们可能会疑问，vip漂移时，vip路由是如何处理的？需要更新路由表对象吗？实际是不需要的。vip漂移时，PrivateVip对象会发生变化，转发面会先匹配vip路由，而后会去根据PrivateVip对象生成的vip和mac的对应关系去查询实际vm。

可以看到，原本也是很复杂的嵌套、级联关系，通过引用模型的解耦变得非常简单。

而路由表对象的include也比较复杂，分为如下几个情况：

- 如果路由表是region默认路由表，那么该字段往往是空的；
- 如果路由表是子网路由表，那么该字段往往会包含region默认路由表的Id；
- 如果路由表是子网路由表，且包含了VPC打通的路由，那么该字段除了包含region默认路由表之外，还会包含打通的VPC的Id；

可以参考当时的部分讨论记录：[讨论纪要](https://ushare.ucloudadmin.com/pages/viewpage.action?pageId=28390905)

---

RouteTable对象的引用关系如下：

| 关系      | 值                     | 含义                    |
| ------- | --------------------- | --------------------- |
| include | routeTableId, vpcId 等 | 路由表对象可以引用其他路由表，或者相关对象 |

#### **VPCShareConnection**

VPC打通(含项目打通)对应的对象我们称为VPCShareConnection，我们会为有打通关系的每个vpc创建一个VPCShareConnection对象。

该对象的引用关系如下：

| 关系      | 值        | 含义                 |
| ------- | -------- | ------------------ |
| owner   | vpcId    | 该打通关系所对应的vpc的vpcId |
| include | vpcId... | 打通的所有对端vpc的vpcId   |

#### **PrivateVip**

为了使得内网高可用VIP的漂移是无状态的，我们也定义了PrivateVip对象，该对象用来表示Vip和实际mac的对应关系。

该对象的引用关系如下：

| 关系    | 值     | 含义               |
| ----- | ----- | ---------------- |
| owner | vpcId | 该VIP所属的vpc的vpcId |

#### **Pipeline**

Pipeline对象没有设置引用关系。

#### **PipelineBinding**

PipelineBinding对象用于关联pipeline和具体的转发面网元，设计该对象的初衷是为了可以支持pipeline的灰度和指定下发部分网元。

对于转发面网元，我们定义了两种scope：

- vswitch级别：每台vswitch(dpagent)注册到dpmgr之后，dpmgr会产生一个vswitch对象，该对象的id值等于dpid。当binding的user设置为该值后，标识只关联到指定的vswitch上，也即某台指定宿主机，具体请参考[vswitch对象](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%83%EF%BC%89%EF%BC%9A%E6%8B%93%E6%89%91%E8%A7%A3%E6%9E%90%E5%92%8C%E6%8E%A8%E9%80%81?id=vswitch%e5%af%b9%e8%b1%a1)；
- global级别：该global指的是某个region，对象的id值等于regionId。当binding的user设置为该值后，标识pipeline会推送到整个region所有的vswitch上，也即region内的全部宿主机上，具体请参考[Global对象](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%83%EF%BC%89%EF%BC%9A%E6%8B%93%E6%89%91%E8%A7%A3%E6%9E%90%E5%92%8C%E6%8E%A8%E9%80%81?id=global%e5%af%b9%e8%b1%a1)；

---

| 关系      | 值             | 含义                                                                                                                                                                                                                                                                                                                                      |
| ------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| user    | scopeId       | scopeId主要有两种：vswitch dpid或者regionId                                                                                                                                                                                                                                                                                                     |
| include | pipelineId... | 引用的所有关联pipelineId                                                                                                                                                                                                                                                                                                                       |
| exclude | pipelineId... | 常用于broadcast状态的pipeline灰度，如：已经设为broadcast状态的pipeline A（继承于[Global对象](http://doc.vpc.ucloudadmin.com/#/vpc3/VPC3.0%E7%B3%BB%E5%88%97%EF%BC%88%E4%B8%83%EF%BC%89%EF%BC%9A%E6%8B%93%E6%89%91%E8%A7%A3%E6%9E%90%E5%92%8C%E6%8E%A8%E9%80%81?id=global%e5%af%b9%e8%b1%a1)）需要灰度时，可以新建一个pipeline binding 引用灰度对象B并设置和A的互斥关系，此时将唯一推送B对象，而不会推送A对象。 |

#### **Firewall**

Firewall对象没有设置引用关系。

#### **FirewallBinding**

| 关系      | 值             | 含义                      |
| ------- | ------------- | ----------------------- |
| owner   | interfaceId   | 该binding所属的interface id |
| include | firewallId... | 关联的firewall Id          |

<!-- tabs:end -->
