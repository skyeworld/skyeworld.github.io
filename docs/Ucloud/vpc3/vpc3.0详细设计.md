# VPC3.0 详细设计

<p align="right"><font color=Grey>try.chen 2019-04-29</font></p>

## 整体架构

![](media/15510108769872/15510142300704.jpg)

## 控制面设计

控制面按照微服务化的理念进行拆分，以对服务实现模块化，解决此前服务不可复用的问题，便于开发和迭代，同时有助于减小故障域。

微服务化的第一步是建立虚拟网络的对象模型，按照对象及对象的方法拆分成不同微服务。

### 对象模型

虚拟网络对象模型如下图所示：

![](media/15510108769872/15510113046479.jpg)

对象模型的定义在 [unet-vpc3/protos/model](https://gitlab.ucloudadmin.com/unet-vpc3/protos/tree/master/model) 中。

#### Interface

Interface对象的定义如下:

```protobuf
message Interface {
    uint64 id = 1;                  // 网卡对象id, 和转发面cookie唯一对应  
    string uuid = 2;                // 可选，如果是弹性网卡，则为弹性网卡Id，对于非弹性网卡，暂为空       
    string mac = 3;                 // 网卡mac     
    repeated IPv4Adress v4 = 4;     // 一个网卡可绑定0或多个IPv4地址
    repeated IPv6Adress v6 = 5;     // 一个网卡可绑定0或多个IPv6地址
    string objectId = 6;            // 绑定对象Id
    ObjectType objectType = 7;      // 绑定对象类型
    string subnetId = 8;            // 网卡所属SubnetId
    string vpcId = 9;               // 网卡所属VPCId
    uint32 account = 10;             // 网卡所属AccountId
    uint64 dpid = 11;               // 网卡对应的datapathId
    uint32 port = 12;               // 网卡对应datapath port
    Version version = 20;           // 网卡对象Version
}
```

#### IPv4

IPv4对象的定义如下:

```protobuf
message IPv4Adress {
    string ip = 1;
    IPType type = 2;
}
```

#### IPv6

#### Subnet

子网(Subnet)对象的定义如下:

```protobuf
message Subnet {
    uint32 id = 1;              // 子网对象Id，和转发面cookie唯一对应
    string uuid = 2;            // 子网资源ID
    string vpcId = 3;           // 子网所属VPCId
    uint32 account = 4;         // 子网所属AccountId
    int32 type = 5;             // 子网类型，区分是否为基础子网
    string cidrBlockV4 = 6;     // 子网关联ipv4地址空间
    string gatewayV4 = 7;       // 子网对应的ipv4网关
    string cidrBlockV6 = 8;     // 子网关联ipv6地址空间
    string gatewayV6 = 9;       // 子网对应ipv6网关
    string routeTableId = 10;   // 子网关联的路由表Id
    Version version = 20;       // 子网对象对应版本
}
```

#### VPC

VPC对象的定义如下:

```protobuf
message VPC {
    uint32 id = 1;                      // vpc对象Id，和转发面cookie唯一对应
    string uuid = 2;                    // vpc资源Id
    uint32 account = 3;                 // vpc所属accountId
    uint32 tunnelId = 4;                // vpc对应的隧道Id，用于overlay租户信息标识
    repeated string cidrBlocksV4 = 5;   // vpc可关联多个ipv4地址空间
    string cidrBlocksV6 = 6;            // vpc可关联一个ipv6地址空间
    int32 type = 7;                     // vpc类型，兼容VPC2.0对象模型，在VPC2.0中标识是否是托管云VPC
    Version version = 20;               // vpc版本
}
```

#### 路由表

路由表(RouteTable)对象的定义如下:

```protobuf
message RouteTable {
    uint32 id = 1;                                      // 路由表对象Id 和转发面cookie唯一对应
    string uuid = 2;                                    // 路由表资源Id
    RouteTableType type = 3;                            // 路由表类型
    string vpcId = 4;                                   // 路由表所属VPC Id
    uint32 account = 5;                                 // 路由表所属Account Id
    repeated RouteRule rules = 6;                       // 路由规则
    repeated string associatedSubntets = 7;             // 路由表关联的子网。一个路由表可被多个子网关联
    Version version = 20;                               // 路由表版本
}

enum RouteTableType {
    RouteTableType_CUSTOM  = 0;    // 自定义路由表，用户创建，关联在子网上（子网路由表）
    RouteTableType_VPC     = 1;    // VPC路由表，主路由表，含VPC系统路由规则。未显式绑定到路由表的子网都绑定在VPC路由表上。
    RouteTableType_REGION  = 2;    // Region路由表，如routetable-public，或者可用区间互通（如北京一和北京二，上海一和上海二）
}

message RouteEntry {
    AddressFamily af = 1;           // 协议版本 IPv4 或 IPv6
    string originAddr = 2;          // 源地址
    string destNetwork = 3;         // 目的网段，不包含掩码
    int32 destNetworkMask = 4;      // 目的网段网络掩码
    int32 priority = 5;             // 路由优先级
    RouteOrigin origin = 6;         // 路由起源，暂为保留字段
    repeated Nexthop nexthops = 7;  // 下一跳
}

message RouteRule {
    string id = 1;                  // RouteRule Id
    RouteEntry entry = 2;
}
```

### 微服务

对应对象模型，控制面微服务包含以下服务：

- InterfaceService
- IPv4Service
- IPv6Service
- SubnetService
- VPCService
- RouteTableService
- ACLService
- MeterService
- QoSService

**InterfaceService** 定义如下：

```protobuf
service InterfaceService {
    rpc Create(CreateInterfaceRequest) returns (CreateInterfaceResponse);
    rpc Delete(DeleteInterfaceRequest) returns (DeleteInterfaceResponse);

    rpc Descirbe(DescirbeInterfaceRequest) returns (DescirbeInterfaceResponse);

    rpc AttachInstance(AttachInstanceRequest) returns (AttachInstanceResponse);
    rpc DetachInstance(DetachInstanceRequest) returns (DetachInstanceResponse);

    rpc AttachIP(AttachIPRequest) returns (AttachIPResponse);
    rpc DetachIP(DetachIPRequest) returns (DetachIPResponse);
}
```

**IPv4Service** 定义如下:

```protobuf
service IPv4Service {
    rpc AllocateIP(AllocateIPRequest) returns (AllocateIPResponse);
    rpc FreeIP(FreeIPRequest) returns (FreeIPResponse);
}
```

**SubnetService** 定义如下:

```protobuf
service SubnetService {
    rpc Create(CreateSubnetRequest) returns (CreateSubnetResponse);
    rpc Delete(DeleteSubnetRequest) returns (DeleteSubnetResponse);
}
```

**VPCService** 定义如下:

```protobuf
service VPCService {
    rpc Create(CreateVPCRequest) returns (CreateVPCResponse);
    rpc Delete(DeleteVPCRequest) returns (DeleteVPCResponse);
    rpc AddCidrBlockV4(AddCidrBlockV4Request) returns (AddCidrBlockV4Response);
    rpc DelCidrBlockV4(DelCidrBlockV4Request) returns (DelCidrBlockV4Response);
    rpc InterconnectVPC(InterconnectVPCRequest) returns (InterconnectVPCResponse);
    rpc DisconnectVPC(DisconnectVPCRequest) returns (DisconnectVPCResponse);
}
```

**RouteTableService** 定义如下:

```protobuf
service RouteTableService {
    // 路由表操作
    rpc Create(CreateRouteTableRequest) returns (CreateRouteTableResponse);
    rpc Delete(DeleteRouteTableRequest) returns (DeleteRouteTableResponse);
    rpc List(ListRouteTableRequest) returns (ListRouteTableResponse);
    rpc Describe(DescribeRouteTableRequest) returns (DescribeRouteTableResponse);
    rpc DescribeSubnetRouteTable(DescribeSubnetRouteTableRequest) returns(DescribeSubnetRouteTableResponse);
    rpc DescribeRegionDefault(DescribeRegionDefaultRouteTableRequest) returns(DescribeRegionDefaultRouteTableResponse);

    // 路由表绑定解绑
    rpc AssociateRouteTable(AssociateRouteTableRequest) returns (AssociateRouteTableResponse);
    rpc DisassociateRouteTable(DisassociateRouteTableRequest) returns (DisassociateRouteTableResponse);

    // 路由规则操作
    rpc AddRule(AddRuleRequest) returns (AddRuleResponse);
    rpc DelRule(DelRuleRequest) returns (DelRuleResponse);
    rpc ModRule(ModRuleRequest) returns (ModRuleResponse);

    // 查询路由表，用于进行路由表查询并返回Nexthop；
    rpc Lookup(RouteLookupRequest) returns (RouteLookupResponse);
}
```

路由规则在数据库中分别保存在t_route_rule和t_route_rule6中，已有的服务包括物理云、托管云、PRM目前不支持IPv6仅仅访问t_route_rule表，但RouteTableService会聚合两张表的内容同时返回。当物理云、托管云、PRM需要支持IPv6时将切换到访问RouteTableService，然后RouteTableService可以考虑重构将两张表合并。

**PipeLineService** 主要负责机制flow的下发，来源于VPC支持的特性，具体见 [VPC特性列表](http://confluence.ucloudadmin.com/pages/viewpage.action?pageId=23523751)

**UVPCFEv2** 负责提供控制台、内部API调用，负责微服务的API调用、整合等，不访问DB，与资源系统、计费等系统交互。

#### 微服务 SLA

微服务提供的API(集群)应满足如下SLA：

- 支持并发 1w ops
- 生效时延 < 3s
- 成功率 99.99%
- 测试覆盖率 > 80%

#### 特性列表

控制面引入微服务化后，会导致服务节点数量增多，以及增加大量网络RPC，这对服务的运维管理、RPC可靠性都带来了挑战，因此微服务化需要实现以下特性以保证可靠性、简化运维管理。

- **灰度能力:** 提供基于ServiceMesh的API灰度能力。客户端进行RPC调用时，应该在GRPC Metadata中携带灰度信息，至少应满足的灰度粒度有:
  
  - OrganizationID
  - TopOrganizationID
  - VipLevel

- **日志监控和告警**（SRE）:
  
  - 日志级别及告警：
    - debug: 默认关闭，可动态开启，用于打印debug信息；
    - info: 默认级别；
    - warn: 无需实时告警，一般是request级别的异常，需运维/研发查看；
    - error: 服务级别异常，实时告警，人工介入处理，需接入noc；
  - 日志需要区分正常和异常日志，warn以下及以上日志输出到不同日志文件；
  - 日志文件格式要求应为json，通过filebeat采集导入elasticsearch；
  - 对于API写操作，记录info级别日志；
  - 与某request相关联的日志应全部带有该请求的`SessionNo`或`RequestId`字段；

- **无损升级:** 微服务升级时，需要通过envoy将流量全部切到其他subset，并查询envoy stats，确认已没有active请求（envoy 管理接口/stats中的downstream_rq_active表示当前活跃请求，定义见[envoy文档](https://www.envoyproxy.io/docs/envoy/latest/configuration/http_conn_man/stats#config-http-conn-man-stats)），才允许升级，以此做到无损升级。由Mafia或者OPService提供API进行服务的无损升级。

![](media/15510108769872/15510135852789.jpg)

- **对账:** 使用缓存的服务应内嵌对账机制，保证缓存数据的一致性；

- **原子性:** API应做到原子性，以避免脏数据问题；

- **幂等:** API应保证幂等，以使上游或者envoy对API进行重试；

- **可靠性：** 微服务可以通过Envoy的熔断、限流、重试等机制提升可靠性，熔断防止服务出现雪崩，限流以提供有损服务；

- **事件发布:** 微服务向`EventService(ES)`进行事件发布时应保证成功，通过如下机制保证：
  
  1. 微服务向ES提交事件(state = init)，若失败则返回失败；
  
  2. 微服务内部的业务逻辑处理；
  
  3. 若第二步成功，则向ES commit，若失败，则向ES abort；
  
  4. 若ES中存在state=init的事件，超时时间后，进行commit；
     
     原则是：事件可以多写，但不能漏写。下游从ES取到事件后，应向数据库进行一次确认。订阅者只能订阅到Commit后的事件。
     
     ![](media/15510108769872/15510141507106.jpg)

#### 事件

微服务对于来自API的变更记录，会产生对应的对象变更事件，并向对象MQ进行发布。

FlowManager会订阅对象变更事件，并通过`FlowInterpreter`将对象解释成OpenFlow后，发布FlowEvent到Flow MQ中。其中，发布的topic因对象而已。

### DPAgent

DPAgent(DatapathAgent) 是运行在宿主机上的Agent，负责OpenFlow的管理及更新，并提供了控制面的运维接口。

DPAgent的定义如下:

```protobuf
service DPAgentService {
    // AddFlows向ovs添加flow
    // AddFlows是原子操作
    rpc AddFlows(AddFlowsRequest) returns (AddFlowsResponse);

    // DelFlows向ovs删除flow
    // DelFlows是原子操作
    rpc DelFlows(DelFlowsRequest) returns (DelFlowsResponse);

    // DumpFlows实现dump flow
    rpc DumpFlows(DumpFlowsRequest) returns (DumpFlowsResponse);

    // FireUpdate用于通知DPAgent立刻调用GetFlow进行更新
    // 可设置忽略版本号的强制更新
    // 常规更新机制依赖于事件通知或者周期更新
    rpc FireUpdate(FireUpdateRequest) returns (FireUpdateResponse);

    // PacketOut用于支持发送PacketOut事件给ovs，通过ovs向外注包
    rpc PacketOut(PacketOutRequest) returns (PacketOutResponse);

    // OFTrace用于支持调用ovs-appctl ofproto/trace，用于巡检、验证等
    rpc OFTrace(OFTraceRequest) returns (OFTraceResponse);

    // TraceRoute通过内部调用PacketOut来获取VM去往特定目的的traceroute信息
    rpc TraceRoute(TraceRouteRequest) returns (stream TraceRouteResponse);

    // 检测接口，用于在Agent端探测连通性、时延
    rpc Inspect(InspectRequest) returns (InspectResponse);

    // 全量检测，DPAgent从本地取出源mac以及所有目的对端
    rpc FullInspect(FullInspectRequest) returns (stream FullInspectResponse);

    // CheckAlive用于验证DPAgent自身功能是否正常
    rpc CheckAlive(CheckAliveRequest) returns (CheckAliveResponse);

    // 对于关心的数据包（如TraceRoute、Inspect中的ICMP Reply）会通过Controller转给DPAgent处理
    rpc PacketIn(PacketInRequest) returns (PacketInResponse);
}
```

#### 工作流程

![工作流程](media/15510108769872/DPAgent-workflow.jpg)

#### 特性列表

- **原子性：** DPAgent 批量更新ovs flow时，需要保证原子，对于ovs2.6及以上版本，可通过`--bundle`来保证，但是对于ovs2.6以下版本，需要DPAgent保证；

- **更新flow:** 对于ovs2.3的ovs-ofctl 子命令 `diff-flows` 和 `replace-flows` 存在不支持table和cookie的问题（初始化为0），因此使用时需DPAgent做兼容；

- **监听Openflow事件:** DPAgent需要监听Openflow PortStatus / FlowRemoved事件：
  
  - 其中对PortStatus的支持，可以后取消目前频繁的port上报机制，并实现port的主动发现；FlowRemoved事件可以保证DPAgent和ovs flow同步的及时性和正确性，避免频繁的dump flow；
  - Port Add时，需要拉取与该mac相关的flow，Port Del时同样需要清理flow；
  - 此外，对于获取port关联的mac地址，应该来源于external_ids中设置的`attached-mac`，而非`mac-in-use`；

- **OVS监控：** 支持对ovs cpu、datapath flow数量、userspace flow数量进行监控，并暴露metrics。监控指标可通过监控平台部门的transfer服务进行上报；

- **存活性：** 外网监控、FlowManager维护连接状态等等，需告警；

- **版本号：** DPAgent会缓存当前mac-cookie-version两级map，收到来自MQ的Event、GetFlowResponse时，会校验其中的Version，只有远端Version大于本地版本才会处理，以此可以做到事件折叠、版本校验等；对于特殊版本（如version=0），Agent会清空本地缓存的version；

- **注意点：**
  
  - **定时任务：** 对于主动定时任务，不依赖于时间戳，因为宿主机时间可能会因为NTP同步而回滚；
  - **Port占用：** Agent发布前，需要先全网验证(lsof)Agent的监听Port是否被占用，防止出现Port被占用无法启动服务的问题；
  - **监听内网IP:** Agent监听时，应监听在管理IP，防止在配有外网IP的宿主机上暴露服务端口；

#### Agent Flow变更流程

FlowEvent定义如下：

```protobuf
message FlowEvent {
    uint64 cookie = 1;
    CookieType type = 2;
    model.Version version = 3;
    model.Event event = 4;            // 微服务对象变更事件
    oneof scope {
        string mac = 5;
        string subnetId = 6;
        string vpcId = 7;
        uint32 account = 8;
    }
}
```

##### 全量更新（非MQ版本）

1. DPAgent首先通过接口`GetCookieByDpid(GetChangedCookieByDpid)`拉取本地关心的cookie列表；
2. DPAgent通过接口`GetFlowsByCookie`根据Cookie拉取对应的flow和版本；
3. DPAgent同步到本地；

##### 增量更新（非MQ版本）

1. DPAgent通过接口`GetChangedCookieByDpid`向上游获取变化的Cookie，该接口请求参数中会携带本地的最新版本号；
2. 该接口会返回变更的Cookie列表；
3. DPAgent通过接口`GetFlowsByCookie`根据Cookie拉取对应的flow和版本；
4. DPAgent同步到本地；

##### MQ版本

1. DPAgent首先会调用全量接口`Get`和`GetFlowByMac`来获取全量flow信息并下发。这两个接口只能分别按照DPID和Mac进行灰度；
2. DPAgent向MQ订阅Flow变更事件，订阅的topic为本地Mac所属VPC；
3. 当DPAgent收到来自MQ的FlowEvent时，DPAgent会根据type和scope进行过滤，判断是否是本地应该关心的事件（如Interface变更是VPC级别，而路由表变更是子网级别，安全组是Interface级别）；
4. 对于本地应该关心的事件，再比较事件中的Version是否大于本地缓存的对应Version，若满足，则向上游FlowManager调用增量接口`GetSpecifiedFlows`，传入FlowEvent中指定的cookie；若不满足，则忽略该事件。其中该接口可按照mac+cookie进行灰度；
5. 收到GetSpecifiedFlows响应消息时，同样进行版本号判断，若版本大于本地缓存版本，则按照指定的cookie更新本地flow，并更新本地缓存版本；
6. Agent定期进行全量更新，或者在收到FireUpdate请求时也会立刻进行全量更新；
7. Agent通过FlowRemoved来获取Flow变化状态，在收到FlowRemoved事件时，会立刻进行本地Flow和上游Flow的同步；

#### 全量巡检

DPAgent设计有巡检机制，支持巡检指定VPC或者指定源目的连通性是否正常。

巡检原理如下：

![](media/15510108769872/15510194501017.jpg)

1. DPAgent通过数据表Flow获取到所有目的IP，并使用所连VM作为源IP（也可通过API指定源目），以此构造ToS染色的ICMP Request，且带有特殊ICMP id/seq，通过 ovs-ofctl packet-out向外发送。
2. 此时，DPAgent会下发一条带有过期时间（时间等于收包时的超时时间）的flow，该flow匹配回程的ICMP Reply，并将数据包发送给DPAgent。Flow中发送给Controller(actions=CONTROLLER:65535)，Controller发送给本地的DPAgent（通过PacketInRequest)；
3. DPAgent通过判断收到的ICMP Reply(根据id/seq过滤)可获取连通性、时延等数据。对于周期性巡检，若发现不通则进行告警，对于API调用，则返回连通性、时延情况。此外，对于回程flow，DPAgent需要验证icmp_reply的对应的output port是否正确;
4. 主动巡检仅检测VPC内的全互联连通性。

是否周期性全量巡检由配置文件指定。

此外，巡检API支持探测时设置参数验证VPC2.0还是VPC3.0的逻辑，区别在于前者的入口位于table_0，后者的入口位于table_2，以此做到可以切换巡检入口，可用于变更前验证。

#### traceroute

DPAgent支持触发traceroute，以获取指定源VM去往目的的traceroute路径，其原理是基于ovs-ofctl packet-out的traceroute。

当触发traceroute时，DPAgent会下发一条匹配回程icmp reply的flow，通过controller中转给DPAgent，之后通过处理，流式返回逐跳路径。

### FlowManager

广义的FlowManager由以下三部分组成：

| 组件                     | 功能                         |
| ---------------------- | -------------------------- |
| FlowManager            | Flow推送模块，和DPAgent进行交互      |
| FlowEventPubService    | 事件通知模块，将Flow变更事件推送到Flow MQ |
| FlowInterpreterService | 将对象解释为Openflow             |

**FlowManager** 的定义如下：

```protobuf
service FlowManager {
    // DPAgent收到事件通知时通过GetFlow来向FlowManager拉取Flow
    // 拉取flow时，有两种粒度，dpid或是mac。dpid获取datapath级别的flow，mac获取与该mac相关的flow
    // 返回的是带有版本、索引的flow集合。索引(cookie)唯一标识这一组flow，DPAgent通过该cookie原子的更新
    // 转发面的相关flow。cookie来源于控制面的某个具体对象。版本号用于标识该cookie对应对象的变更记录，
    // DPAgent通过版本号可确认flow变更记录。

    // 根据dpid拉取datapath关心的全量cookie。对于宿主机该逻辑是：根据dpid获取关联的mac，根据mac获取VPC，根据VPC获取
    // 该VPC下的Cookie。对于无port、mac的网元来说（如CNAT2、SDNGW），通过dpid识别其身份后，通过其他逻辑返回对应的cookie。
    rpc GetCookieByDpid(GetCookieByDpidRequest) returns (GetCookieByDpidResponse);

    // 如果每次都返回全量cookie列表，会导致消息体很长，效率较低。因此，常态下，DPAgent通过该接口增量获取变化的Cookie。
    // 基本原理是：DPAgent请求中携带本地最新版本号，FlowManager收到该版本号后，通过比较，返回增量变化的cookie。
    // FlowManager计算增量变化的cookie原理是：维护vpc-cookie-version的全局缓存，通过vpc作为key、并以DPAgent
    // 中携带的version作为二级key查找，寻找增量更新的cookie并进行返回。
    rpc GetChangedCookieByDpid(GetChangedCookieByDpidRequest) returns(GetChangedCookieByDpidResponse);

    // 该接口根据cookie返回与其对应的flow和版本。
    rpc GetFlowsByCookie(GetFlowsByCookieRequest) returns(GetFlowsByCookieResponse);
}
```

**FlowEventPubService** 的定义如下:

```protobuf
service FlowEventPubService {
    rpc Pub(PubEventRequest) returns(PubEventResponse);
}
```

**FlowInterpreterService** 的定义如下：

```protobuf
// FlowInterpreter用于将Object解释为openflow。
    rpc InterfaceToFlows(InterfaceToFlowsRequest) returns (InterfaceToFlowsResponse);
    rpc RouteTableToFlows(RouteTableToFlowsRequest) returns (RouteTableToFlowsResponse);
    rpc IPToFlows(IPToFlowsRequest) returns (IPToFlowsResponse);
}
```

#### 工作流程

![工作流程](media/15510108769872/FlowManager-workflow.jpg)

#### 缓存

- FlowManager为了避免频繁的GetFlow对上游的带来的压力，需要将Flow缓存到Redis中；
- FlowManager主节点需要对Redis进行对账，以保证数据的正确性；
- 此外，Redis的高可用方案如果使用Sentinel机制，则默认请求都发送给Master节点，会导致Master负载过高，而Slave处于闲置状态。因此，应通过Sentinel拿到Slave的状态后，将读请求分担到Slave上;
- Redis中缓存的数据结构为hash表，key为cookie，value为版本及flow；

**缓存更新流程:**

![](media/15510108769872/15510606600581.jpg)

1. update并发安全：通过eval保证操作的原子性，仅当key满足以下条件之一时，才可更新cache内容：
   
   - cache中无此次更新的key；
   - cache中缓存该key的version低于此次更新的version

2. 事件折叠：只有当以下条件满足时，agent才会向上游请求更新：
   
   - notify中的版本号大于当前本地缓存的最新版本号

3. response并发安全：
       只有当以下条件满足时，agent才会使用response更新本地缓存：
   
   - 本地缓存的key不存在；
   - response中版本大于本地缓存的版本；
   - 当version=0时，agent会删除本地缓存的所有版本；

#### FlowEvent

FlowManager会将对象事件转换为Flow变更事件，如上所述，FlowEvent的定义如下：

```protobuf
// CookieType标识了事件类型
// CookieType=Interface, VPC级别变更事件, VPC内所有实例都要处理该事件
// CookieType=RouteTable, 子网级别变更事件, 只有Event中子网相符的实例才需要处理该事件
// CookieType=ACL, 子网级别变更事件, 只有Event中子网相符的实例才需要处理该事件
// CookieType=SecurityGroup, 实例级别事件，只有和Evnet中mac相符的实例才需要处理该事件
// CookieType=Meter, 实例级别事件，只有和Evnet中mac相符的实例才需要处理该事件
// CookieType=QoS, 用户级别事件，只有和Evnet中account相符的实例才需要处理该事件
message FlowEvent {
    uint64 cookie = 1;
    CookieType type = 2;
    model.Version version = 3;
    model.Event event = 4;            // 微服务对象变更事件
    oneof scope {
        string mac = 5;
        string subnetId = 6;
        string vpcId = 7;
        uint32 account = 8;
    }
}
```

对象事件推送范围：

| 对象        | 类型          | topic | 推送范围            |
| --------- | ----------- | ----- | --------------- |
| Interface | -           | VPC   | VPC             |
| IP        | -           | VPC   | VPC             |
| 路由表       | 子网路由表       | VPC   | 设置子网过滤条件        |
| 路由表       | VPC系统路由表    | VPC   | VPC             |
| 路由表       | Region系统路由表 | VPC   | 所有VPC           |
| ACL       | -           | VPC   | 设置子网过滤条件        |
| 安全组       | -           | VPC   | 设置Interface过滤条件 |

#### Cookie 定义

Flow推送时，通过Cookie作为唯一键将一组flow和对象进行关联，DPAgent通过cookie原子获取、更新一组flow。

cookie的定义如下：

```protobuf
// Cookie由16bit CookieType和48bit Cookie id组成
enum CookieType {
    Interface = 0;
    RouteTable = 1;
    ACL = 2;
    SecurityGroup = 3;
    Meter = 4;
    QoS = 5;
}
```

Cookie Id因对象而已，定义在各对象的`id`属性中。

#### 事件变更流程

1. FlowManager订阅对象MQ，获取到对象变更事件后，调用微服务接口拉取最新数据后，更新Redis，并发布FlowEvent到Flow MQ；
2. FlowManager接受DPAgent的GetFlow请求，优先从Redis读取缓存的Flow，如果miss则从上游微服务构建；

#### 灰度

FlowManager支持如下灰度:

| 接口                | 类型   | 灰度能力                  |
| ----------------- | ---- | --------------------- |
| GetFlowByDpid     | 全量接口 | 按照DPID灰度              |
| GetFlowByMac      | 全量接口 | 按照Mac(Account)等灰度     |
| GetSpecifiedFlows | 增量接口 | 按照cookie、cookieType灰度 |

## MQ

MQ分为两层，上层MQ用于对象事件的发布，发布者为微服务控制面，订阅者为FlowManager。

FlowManager会将对象事件转换为Flow变更事件，对象ID转换为Cookie，对象翻译为Openflow，最后发布到下层MQ，订阅者为DPAgent。

DPAgent收到该事件后，通过事件中的Cookie向FlowManager拉取Flow及版本。

### 分片

## 结构化Flow设计

> 详细flow设计见：[vpc3.0 flow设计](https://gitlab.ucloudadmin.com/unet-vpc3/docs/blob/master/vpc3.0%20flow设计.md)

**出入向判断**

根据对VM的数据流向，将pipeline分为出入向两种。

出入向的区分通过以下逻辑区分：

![](media/15510108769872/flow-bound.jpg)

### 入向表

![-w727](media/15510108769872/inbound-pipeline.png)

其中，版本控制用于控制跳转流程，如VPC2.0向VPC3.0切换。灰度控制用于判断是否需要将指定用户流量灰入v3逻辑中。灰度控制在下文中会详述。

v3 pipeline中的跳转控制流表由pipeline service下发，通过pipeline控制后续的table之间的跳转逻辑。

镜像：本意是保证即使灰度到VPC3.0后，table_0中的flow依然正常下发，防止回退时，下发大量flow。但镜像会导致同一个包被发送两次，除非侵入性的修改原有逻辑。

### 出向表

![-w849](media/15510108769872/outbound-pipeline.png)

其中，安全组和acl中应该默认放行以下协议：

- ARP
- ICMPv6
- DHCP
- DHCPv6

### forward 表

![-w1081](media/15510108769872/forward-pipeline.png)

### pipeline

![-w528](media/15510108769872/pipeline.png)

flow示例如下：

```bash
# table 2
# pipeline
# 通过metadata作为状态机ID，依次resubmit到相应的表中执行

# 跳转到入向hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x0 actions=set_field:0x0->metadata,resubmit(,3),set_field:0x10->metadata,resubmit(,3)
# 跳转到入向转发前hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x10 actions=set_field:0x0->metadata,resubmit(,4),set_field:0x20->metadata,resubmit(,3)
# 跳转到转发表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x20 actions=set_field:0x0->metadata,resubmit(,40),set_field:0x30->metadata,resubmit(,3)
# 跳转到入向转发后hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x30 actions=set_field:0x0->metadata,resubmit(,5),set_field:0x40->metadata,resubmit(,3)
# 跳转到入向ACL表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x40 actions=set_field:0x0->metadata,resubmit(,6),set_field:0x50->metadata,resubmit(,3)
# 跳转到入向安全组
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x50 actions=set_field:0x0->metadata,resubmit(,7),set_field:0x60->metadata,resubmit(,3)
# 跳转到入向output前hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x60 actions=set_field:0x0->metadata,resubmit(,8),set_field:0x70->metadata,resubmit(,3)
# 跳转到入向output表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x70 actions=set_field:0x0->metadata,resubmit(,9),set_field:0x80->metadata,resubmit(,3)
```

### 数据表

定义如下数据表：

| 功能             | 表项  |
| -------------- | --- |
| MAC信息查询        | 200 |
| MAC查询IPv4      | 201 |
| MAC查询IPv6      | 202 |
| IPv4查询MAC      | 203 |
| IPv6查询MAC      | 204 |
| MAC查询DPID/PORT | 205 |
| DPID查询Datapath | 206 |
| IPv4路由表查询      | 207 |
| IPv6路由表查询      | 208 |
| VIP表           | 209 |
| QoS表           | 210 |
| 灰度表            | 211 |

目前现网已使用如下table：0, 1, 100, 101, 110, 111, 115, 120。

---

## 运维工具

### 连通性排查工具

OPService提供连通性排查工具。

输入：源目IP，选择场景（同Flow回归测试中的场景）
输出：

- 若是连通性探测（Ping），通过DPAgent或BigBrother探测连通性是否正常
- 利用 of-trace（调用DPAgent接口），打印出trace的结果（解析、翻译），输出依次匹配的table、设置的寄存器、跳转流程、最终封装的数据包（或动作）等
- 输出所有匹配到的数据flow的版本是否为最新版本

### 灰度系统

OPService提供灰度API，集成到Mafia中，方便后续的VPC3.0灰度，操作逻辑类似于目前的UXR灰度系统。

## 对账

结构化Flow对账保证datapath flow和cache中的数据是完全一致的，后续Redis对账cache和上游（DB）是完全一致的，通过这种两段式的对账，主要是为了加快对账速度。

### 结构化Flow对账

结构化Flow对账由DPAgent发起，主要保证ovs flow和redis中缓存的数据集是完全一致的。常态下的更新来自于MQ事件的触发，但DPAgent会通过周期性的拉取FlowManager并更新本地flow（如果远端Flow 版本大于本地），保证始终以上游为准。

### Redis对账

Redis对账用于保证Redis（Flow Cache）中缓存的数据和上游Service中的数据是一致的。
对账需要确认以下两种情况：

- Redis中缓存的数据集版本与上游不一致，此为绝大部分情况；
- Redis与上游版本一致，但实际内容不一致，此为少数情况。

第一种情况中，由于每个数据集都带有唯一递增的版本号，因此确认版本是否一致对账成本较小（通过cookie拉取最新版本）；
第二种情况，一般为软件BUG、异常写入等，需要和上游对账数据集和版本号，成本较高。

FlowManager内嵌该对账机制。可以部署单独的节点，开启对账功能。

## 巡检

通过DPAgent的分布式巡检，具有快速全量巡检整个Region内VPC中所有VM的连通性能力，为运维、对账、变更验证提供有力工具。

DPAgent具有探测VM去往连通域内所有目的IP连通性的能力，DPAgent提供巡检接口来支持外部触发巡检，同时内部会周期性保持巡检（通过配置开关）。

**开销预估**

巡检需要需要有开关可动态调整是否开启巡检，并限定巡检的速率。

最大开销计算：

- 按照每台DPAgent连接20台VM计算（实际一般为10~15），每台VM所在VPC拥有5000台VM
- 每个ICMP request占据64bytes

则一次巡检周期中，需要：

- 发送20*5000 = 10w ICMP request
- 发送流量为 6 Mb

按照100 pps的速率计算，巡检一次需要 16 min。

## 变更验证

### 控制面上线验证

VPC3.0控制面服务上线后，需要验证控制面和VPC2.0的逻辑（场景、特性验证）是否一致，通过如下机制保证：

- URouteManager HandlePacketIn Response前增加旁路逻辑，将此次的请求和响应镜像给 OPService；
- OPService通过HandlePacketIn Request 和 Response 构造出探测的数据包和 Overlay 封装后的数据包，并向DPAgent发送 of-trace 请求（调用ovs-appctl ofproto/trace并解析输出），验证此次请求是否正确；

![](media/15510108769872/15510663859742.jpg)

此外，也可部署到指定agent，通过解析controller的request、response，本地调用DPAgent。

### 灰度前置验证

将指定VM灰入VPC3.0逻辑前，OPService需要验证该宿主机上所有的结构化flow是否已能正常工作（连通性验证），通过DPAgent提供的巡检能力，即可进行探测。

探测的源为此次变更的VM，目的来自River收集的table_0中的最近7天通信过的活跃flow（活跃pair）。对于路由flow，如HCGW/VPNGW/SDNGW由于没有具体目的IP，故无较好的验证方法（托管依赖网络位全0的IP）。

取得探测源目IP后，调用DPAgent的注包能力，原理等同于上述 巡检-① 中所述，区别在于DPAgent调用的命令类似于 ovs-ofctl packet-out br0 in_port resubmit:2 packet 通过指定 "resubmit:2" 来使巡检逻辑直接跳转到VPC3.0的逻辑，以此验证VPC3.0逻辑是否正确。

![](media/15510108769872/15510664586843.jpg)

此外，此步应使用全量验证配合，全量验证不要求时效性，只需验证最终结果。

### API变更验证

针对微服务API(gRPC)的回归测试，如创建VPC、子网等等。
由测试同学配合开发API(gRPC)的自动回归测试系统。

### Flow场景回归测试

对于VPC的特性提供BDD风格的测试用例，其中需求为VPC的功能点或者特性，如同子网的两台VM可互相ARP获取到对端Mac，并通过如下流程进行黑盒测试：

- 创建数据和环境（VPC、子网、VM等），并通过VM内的功能测试，验证场景符合期望（如arping 10.1.1.1可正确获取到对端Mac）

其中，为了轻量级的进行回归测试验证，可通过创建veth pair来避免创建VM验证。因此DPAgent支持创建veth pair（给定ip、mac），并支持namespace内的命令操作（如 ping/arping/arp/ip等），并返回stdout/stderr。但此种方式具有局限性，即只支持宿主机内置命令。

测试结束之后，所有创建的veth口被回收和释放。

### 控制面变更验证

灰入VPC3.0后的控制面变更验证，按照服务分为以下几种。

**微服务：**

微服务通过API回归测试，保证正确性。

**FlowManager：**

分为两种验证方式：

- Flow验证：通过验证新老版本通过GetFlow接口获取的Flow是否一致进行验证；
- 连通性验证：通过BigBrother进行活跃Flow的验证；
- Flow场景验证：灰入测试账号到新版本FlowManager后，运行Flow场景集成测试；

连通性验证示意图如下：

![](media/15510108769872/15510665004344.jpg)

## 灰度

VPC3.0 灰度流程如下：
![](media/15510108769872/15510670853621.jpg)

### 控制面灰度

微服务API通过Envoy在GRPC MetaData中设置的 x-ucloud-routeby 携带的信息进行灰度，对于控制面可做到VPC、Account、公司、客户等级等灰度粒度。

![](media/15510108769872/15510666779928.jpg)

细粒度的灰度能力：
![](media/15510108769872/15510667174103.jpg)

### 转发面灰度

在结构化flow中入口处预留了一张灰度表（table_211），用于转发面确定是否灰入VPC3.0的逻辑，粒度是VM（Mac）。默认规则是走原先的VPC2.0（table_0）逻辑，只有明细下发了灰度VPC3.0的条目后，才会灰入VPC3.0逻辑。

## 外部依赖

### River支持VPC3.0

由于结构化flow上线后，无法根据单独一条flow获取源目，因此River需要对VPC3.0做适配。