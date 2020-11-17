# 线上运营API

<p align="right"><font color=Grey>try.chen 2020-10-21</font></p>

## 线上管理接口

以下服务提供了运维接口用于问题诊断、状态巡检等。

### DPMgr

#### 通用信息

由于dpmgr是多节点部署，因此每个response的响应中都带有返回此次response的节点的信息，这些信息位于header中。具体如下：

```toml
HTTP/1.1 200 OK
cluster: s1
content-type: application/json; charset=utf-8
domain: a2.uae
instance: dpmgr-s1-8494547f7d-hbpw5
namespace: prj-vnpd-vpc3
service: dpmgr
date: Sat, 15 Aug 2020 07:26:13 GMT
content-length: 51
x-envoy-upstream-service-time: 0
server: istio-envoy
```

| Key       | Value                     |
| --------- | ------------------------- |
| namespace | prj-vnpd-vpc3             |
| domain    | a2.uae                    |
| service   | dpmgr                     |
| cluster   | s1                        |
| instance  | dpmgr-s1-8494547f7d-hbpw5 |

#### /cache：查询缓存对象

dpmgr内存中维护了全量的flow对象(`BridgeObject`)信息，因此通过`/cache`接口我们可以查询dpmgr缓存的对象信息。

| URI          | Method |
| ------------ | ------ |
| /admin/cache | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |
| id   | 需要查询的对象id                                  | 0     |

响应：

```json
{
  "1153202979583557723": {
    "id": 1153202979583557723,
    "version": 60,             // 对象版本号
    "content": {
      "bridge": "br0",
      "flows": [
        "cookie=0x100100000000005b, table=241,priority=0 actions=load:0->NXM_NX_REG1[]",
        "cookie=0x100100000000005b, table=219,priority=0 actions=load:0->NXM_NX_REG1[]"
      ],
      "affinity": 40        // 对象ovs版本亲和性，OvsVersionAffinity 定义在https://git.ucloudadmin.com/vnpd/protos/blob/master/datapath/bridge.proto
    },
    "owner": 666888        // 对象引用关系
  }
}
```

#### /relations：查询引用关系

dpmgr内存中维护了对象间的引用关系，通过该接口可以查询内存中的引用关系信息。

| URI              | Method |
| ---------------- | ------ |
| /admin/relations | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |
| id   | 需要查询的对象id                                  | 0     |

响应：

```json
{
  "1155454779397251145": {
    "Owns": {
      // false无实际含义，只是利用了golang的map作为set
      "1154982350175223084": false,
      "1154982350182896931": false
    },
    "Uses": {}
  }
}
```

#### /find_related: 模拟拓扑解析（查询与指定对象相关的对象）

find_related用于模拟拓扑解析的过程，并返回出所有相关的对象，通过该api可以方便的debug一些binding对象的推送等。

| URI                 | Method |
| ------------------- | ------ |
| /admin/find_related | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |
| id   | 需要查询的对象id                                  | 0     |

响应：

```json
{
  "1000003": {
    "id": 1000003,
    "version": 100,
    "content": {
      "bridge": "br0"
    }
  },
  "1153202979583557643": {
    "id": 1153202979583557643,
    "version": 17,
    "content": {
      "bridge": "br0",
      "flows": [
        "cookie=0x100100000000000b, table=1,priority=40000,metadata=1 actions=set_field:0->metadata,goto_table:2",
        "cookie=0x100100000000000b, table=219,priority=0 actions=load:0->NXM_NX_REG1[]"
      ],
      "affinity": 40
    },
    "owner": 1000003
  },
  "1159395429072431622": {
    "id": 1159395429072431622,
    "version": 121812728,
    "content": {
      "bridge": "br0",
      "flows": [
        "cookie=0x101700000012ea06, table=208,priority=30000,ipv6,ipv6_dst=0::0/0 actions=load:1->NXM_NX_REG1[],load:5->NXM_NX_REG2[],load:1->NXM_NX_REG7[],set_field:172.16.44.1->tun_dst"
      ]
    },
    "owner": 1000003
  }
}
```

#### /watchers: 查询连接的DPAgent信息

该接口对排查问题非常有效，可以快速获取dpagent的port、object、连接时间等信息，对于确认某些对象是否推送到指定dpagent很有帮助。

| URI             | Method |
| --------------- | ------ |
| /admin/watchers | GET    |

参数：

| 参数   | 含义                                                                        | 默认值   |
| ---- | ------------------------------------------------------------------------- | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value                                | false |
| id   | 需要查询的对象id，该值等同于dpagent的管理ip，<br/>如果为空则返回所有客户端的brief信息，否则会返回一个客户端的detail信息 | 空     |

响应：

```json
// brief 信息
{
  "192.168.152.41": {
    "Id": "192.168.152.41",
    "Type": "uhost",
    "Summary": null,
    "LocalInterfaces": [
      1154419400227763443,
      1154419400222132422,
      666888,
      217840626171204
    ],
    "GlobalVersion": 440421556,
    "ConnectionTime": "2020-07-23 20:06:35",
    "MainGID": 2925,
    "RecvGID": 2927,
    "LoopGID": 2926
  }
}


// detail 信息
{
  "192.168.152.41": {
    "Id": "192.168.152.41",
    "Type": "uhost",
    "Summary": {
      "br0": {
        "dpid": "217840626171204",
        "ports": {
          "111": {
            "uuid": "52:54:00:00:EC:13",
            "name": "vethltest4",
            "ofport": 111,
            "mac": "52:54:00:00:EC:13"
          },
          "112": {
            "uuid": "52:54:00:48:59:30",
            "name": "vethlnsdash",
            "ofport": 112,
            "mac": "52:54:00:48:59:30"
          }
        },
        "objects": {
          // 对象id和版本的映射
          "1154982350182260138": 97627052,
          "1159395429071206316": 45869016,
          "666888": 100
        }
      }
    },
    "LocalInterfaces": [
      1154419400225095523,
      1154419400222132422,
      666888,
      217840626171204
    ],
    "GlobalVersion": 440421556,
    "ConnectionTime": "2020-07-23 20:06:35",
    "MainGID": 2925,
    "RecvGID": 2927
  }
}
```

#### /status：状态信息

该接口主要提供状态信息，用于了解服务的整体运行情况和内存状态等。

| URI           | Method |
| ------------- | ------ |
| /admin/status | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |

响应：

```json
{
  "Watchers": 497,
  "Objects": 159081,
  "BackupOff": false
}
```

返回项具体含义如下：

| key       | value  | 含义                    |
| --------- | ------ | --------------------- |
| Watchers  | 497    | 当前dpmgr节点连接的dpagent数量 |
| Objects   | 159081 | 当前dpmgr节点内存中维护的全量对象数量 |
| BackupOff | false  | 是否开启备份（只针对s0集群有效）     |

#### /offline: 下线指定client

该接口会关闭对应client的stream，以此触发client重连，主要场景用于dpmgr的灰度。

| URI            | Method |
| -------------- | ------ |
| /admin/offline | PUT    |

参数：

| 参数  | 含义                                                                              | 默认值 |
| --- | ------------------------------------------------------------------------------- | --- |
| id  | 需要下线的对象id，该值等同于dpagent的管理ip<br/>如果为空则会将该dpmgr所连接的所有dpagent下线，否则只下线指定id的dpagent。 | 空   |

响应：

```json
{
  "code": 0,    // return code
  "count": 1    // 下线的dpagent数量
}
```

#### /backup: 开关s0集群的备份功能

该接口可以手动开关备份集群(s0)是否进行备份，主要场景为默认集群切换到容灾集群(s9)时，可选择是否停止s0的实时备份，如果短时间内无法恢复，则应该关闭s0的备份，否则会导致s9追上最新变更。

| URI           | Method |
| ------------- | ------ |
| /admin/backup | PUT    |

参数：

| 参数  | 含义           | 默认值 |
| --- | ------------ | --- |
| off | 应填true或false | nil |

响应：

```json
{
    "code": 0,
    "off": true
}
```

### Resource-Service

#### /subjects: 查询订阅信息

该API会返回当前服务内存中构建的来自client的订阅信息，用于帮助排查客户端（如dpmgr、flowservice等）是否连接正常。

| URI             | Method |
| --------------- | ------ |
| /admin/subjects | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |

响应：

```json
{
  "dpmgr.s2": {
    "name": "dpmgr",
    "subset": "s2",
    "types": [
      "type.googleapis.com/datapath.BridgeObject"
    ],
    "accounts": [
      {}
    ],
    "fullUpdateWhenOnline": true
  },
  "flowservice": {
    "name": "flowservice",
    "types": [
      "type.googleapis.com/model.VPC",
      "type.googleapis.com/model.Subnet",
      "type.googleapis.com/model.Interface",
      "type.googleapis.com/model.VPCShareConnection",
      "type.googleapis.com/model.PrivateVIP"
    ],
    "accounts": [
      {}
    ]
  }
}
```

#### /subjectIndex：查询订阅索引

该API和`/subject`类似也是用于订阅信息的查询，但返回的是经过处理后的索引结构，通过该接口可以帮助判断对象的分发、subset的选择等。

| URI                 | Method |
| ------------------- | ------ |
| /admin/subjectIndex | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |

响应：

```json
{
  "dpmgr": {
    "Name": "dpmgr",
    "Group": false,
    "Subsets": {
      "s2": true
    },
    "Types": {
      "type.googleapis.com/datapath.BridgeObject": true
    },
    "Masks": [
      0
    ],
    "Index": {
      "0": {
        "0": "s2"
      }
    }
  },
  "flowservice": {
    "Name": "flowservice",
    "Group": false,
    "Subsets": {},
    "Types": {
      "type.googleapis.com/model.Interface": true,
      "type.googleapis.com/model.PrivateVIP": true,
      "type.googleapis.com/model.Subnet": true,
      "type.googleapis.com/model.VPC": true,
      "type.googleapis.com/model.VPCShareConnection": true
    },
    "Masks": [
      0
    ],
    "Index": {
      "0": {
        "0": ""
      }
    }
  }
}
```

#### /watchers: 查询连接的客户端信息

该接口用于查询当前服务连接的客户端信息，和dpmgr的`/watchers`接口功能类似。

| URI             | Method |
| --------------- | ------ |
| /admin/watchers | GET    |

参数：

| 参数   | 含义                                         | 默认值   |
| ---- | ------------------------------------------ | ----- |
| json | 是否返回json格式<br/>false的话会返回struct type和value | false |

响应：

```json
{
  "dpmgr-s2-6f76f85567-68ff6": {
    "Id": "dpmgr-s2-6f76f85567-68ff6",
    "Subject": {
      "name": "dpmgr",
      "subset": "s2",
      "types": [
        "type.googleapis.com/datapath.BridgeObject"
      ],
      "fullUpdateWhenOnline": true
    },
    "GoroutineId": 140575486,
    "SubscribeSubject": "dpmgr.s2",
    "SubscribeQueue": "",
    "ConnectionTime": "2020-07-23 00:51:20"
  }
  "flowservice-s1-dd798d884-4wlk6": {
    "Id": "flowservice-s1-dd798d884-4wlk6",
    "Subject": {
      "name": "flowservice",
      "types": [
        "type.googleapis.com/model.VPC",
        "type.googleapis.com/model.Subnet",
        "type.googleapis.com/model.Interface",
        "type.googleapis.com/model.VPCShareConnection",
        "type.googleapis.com/model.PrivateVIP"
      ]
    },
    "GoroutineId": 9551426,
    "SubscribeSubject": "flowservice",
    "SubscribeQueue": "",
    "ConnectionTime": "2020-07-14 18:15:31"
  }
}
```

### Pipeline-Service

#### CreatePipeline: 创建一条pipeline

该RPC会向DB插入一条记录，并向event-service发送一个事件，返回完整的pipeline对象。

```protobuf
message CreatePipelineRequest {
    bool custom = 1; // true表示请求需要提供flow，不包含cookie，false表示请求无需提供flow，由flow服务生成
    model.PipelineType type = 2; // 表示每条pipeline的使用方类型
    repeated string flows = 3; // custom为true时pipeline包含的全部flow，不包含cookie
    string remark = 4; // pipeline功能的描述
    datapath.OvsVersionAffinity affinity = 5; // ovs的版本，custom为false时可用于flow服务生成不同版本的flow
}
```

#### DeletePipeline: 删除指定pipeline

该RPC会将DB中指定的pipeline标记为删除，并向event-service发送一个事件。

```protobuf
message DeletePipelineRequest {
    string pipelineId = 1; // 指定要删除的pipelineId
}
```

#### DescribePipeline: 查询所有或指定pipeline

该RPC会向DB中查询所有未删除或指定未删除的pipeline，返回对应完整的pipeline对象。

```protobuf
message DescribePipelineRequest {
    oneof scopeFilter {
        com.Uint64Filters ids = 1; // DB自增id，目前未实现
        com.StringFilters pipelineIds = 2; // 指定要查询的pipelineId，为空表示查询所有未删除的pipeline
    }
}
```

#### DescribePipelineInCache: 查询指定pipeline

该RPC会向resource-service中查询指定的pipeline，返回对应完整的pipeline对象。

```protobuf
message DescribePipelineInCacheRequest {
    repeated string pipelineIds = 1; // 指定要查询的pipelineId
}
```

#### UpdatePipeline: 更新指定pipeline

该RPC会将DB中指定的pipeline进行更新，并向event-service发送一个事件。

```protobuf
message UpdatePipelineRequest {
    string pipelineId = 1; // 指定要更新的pipelineId
    bool custom = 2; // true表示请求需要提供flow，需要提供正确的cookie，可以通过查询获得，false表示请求无需提供flow，由flow服务生成
    model.PipelineType type = 3; // 表示每条pipeline的使用方类型
    repeated string flows = 4; // custom为true时pipeline包含的全部flow，需要提供正确的cookie
    string remark = 5; // pipeline功能的描述
    datapath.OvsVersionAffinity affinity = 6; // ovs的版本，custom为false时可用于flow服务生成不同版本的flow
}
```

#### UpdatePipelineVersion: 更新指定pipeline版本

该RPC会将DB中指定的pipeline自增版本号，并向event-service发送一个事件。

```protobuf
message UpdatePipelineVersionRequest {
    string pipelineId = 1; // 指定要更新的pipelineId
}
```

#### UpdatePipelineBroadcast: 更新指定pipeline是否广播

该RPC会将DB中指定的pipeline标记为是否广播，并向event-service发送一个事件。

```protobuf
message UpdatePipelineBroadcastRequest {
    string pipelineId = 1; // 指定要更新的pipelineId
    bool broadcast = 2; // true表示pipeline会推送到region内所有机器，false表示推送到binding指定的机器
    string token = 3; // broadcast为true时需要token检验防止误操作
}
```

#### CreatePipelineCheckTask: 触发所有或指定pipeline对账

该RPC会将所有未删除或指定未删除的pipeline进行DB与resource-service一致性检查，不一致会重新写入resource-service，返回对账的taskId。

```protobuf
message CreatePipelineCheckTaskRequest {
    string pipelineId = 1; // 指定要对账的pipelineId，为空表示对账所有未删除的pipeline
}
```

#### CreatePipelineBinding: 创建一条binding

该RPC会向DB插入一条记录，并向event-service发送一个事件，返回完整的binding对象。

```protobuf
message CreatePipelineBindingRequest {
    string bindingId = 1; // 表示datapath id
    repeated string pipelines = 2; // 表示该binding需要关联的pipelineId列表
}
```

#### DeletePipelineBinding: 删除指定binding

该RPC会将DB中指定的binding标记为删除，并向event-service发送一个事件。

```protobuf
message DeletePipelineBindingRequest {
    string bindingId = 1; // 指定要删除的bindingId
}
```

#### DescribePipelineBinding: 查询所有或指定binding

该RPC会向DB中查询所有未删除或指定未删除的binding，返回对应完整的binding对象。

```protobuf
message DescribePipelineBindingRequest {
    oneof scopeFilter {
        com.Uint64Filters ids = 1; // DB自增id，目前未实现
        com.StringFilters bindingIds = 2; // 指定要查询的bindingId，为空表示查询所有未删除的binding
        com.StringFilters pipelineIds = 3; // 查询关联指定pipelineId未删除的binding，为空查询所有未关联pipeline未删除的binding
    }
}
```

#### DescribePipelineBindingInCache: 查询指定binding

该RPC会向resource-service中查询指定的binding，返回对应完整的binding对象。

```protobuf
message DescribePipelineBindingInCacheRequest {
    repeated string bindingIds = 1; // 指定要查询的bindingId
}
```

#### UpdatePipelineBinding: 更新指定binding

该RPC会将DB中指定的binding进行更新，并向event-service发送一个事件。

```protobuf
message UpdatePipelineBindingRequest {
    string bindingId = 1; // 指定要更新的bindingId
    repeated string pipelines = 2; // 指定需要关联的全部pipelineId
}
```

#### UpdatePipelineBindingVersion: 更新指定binding版本

该RPC会将DB中指定的binding自增版本号，并向event-service发送一个事件。

```protobuf
message UpdatePipelineBindingVersionRequest {
    string bindingId = 1; // 指定要更新的bindingId
}
```

#### CreatePipelineBindingCheckTask: 触发所有或指定binding对账

该RPC会将所有未删除或指定未删除的binding进行DB与resource-service一致性检查，不一致会重新写入resource-service，返回对账的taskId。

```protobuf
message CreatePipelineBindingCheckTaskRequest {
    string bindingId = 1; // 指定要对账的bindingId，为空表示对账所有未删除的binding
}
```
