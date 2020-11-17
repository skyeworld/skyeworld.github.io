# Sandbox原理及使用指南

<p align="right"><font color=Grey>try.chen 2020-10-30</font></p>

## 可怕的预发布

UCloud的预发布环境向来都是一言难尽，每次使用前都得花个几天时间联系各个部门的人修好各种依赖环境，如此往复。这也对自动化测试造成了很大的困难和阻碍，为了解决这个问题，我们推出了Sandbox解决方法：**通过创建Network Namespace来mock底层云主机，从而屏蔽底层环境**。

## 方案设计

Sandbox在设计的时候遵循了如下原则和目标：

- **API兼容性：** 对于现有Uhost的自动化测试可以无倾入支持sandbox；

- **节点多样性：** Sandbox节点支持Namespace、Docker或是UHost；

- **易用性：** 支持SSH进入Sandbox节点进行测试和管理；

为了达成如上目标，我们设计了如下方案：

![](media/sandbox-1.png)

整个平台分为三个模块组成，分别是`Truman-Server`、`Truman-Gateway`和`Truman-Worker`，外加组件：`CoreDNS`和`Etcd`。

### Truman-Server

#### API设计

传统调用Uhost的方式即通过[Ucloud Public API](https://docs.ucloud.cn/api/summary/README)来调用主机部门的公共API，为了获得**API兼容性**，因此我们决定实现UHost的核心API：包括创建、删除、展示、开关机和迁移等，这样适用方只需要将 BaseURL 从`http://api.ucloud.cn`更改为`http://sandbox.vpc.ucloudadmin.com`即可完成切换和使用。

因此，Truman-Server提供了Sandbox的操作API，并完全支持[ucloud/ucloud-sdk-go](https://github.com/ucloud/ucloud-sdk-go)中主机的关键Public API和全部参数。



目前支持的Public API如下：

```go
package mock
import (
	real "github.com/ucloud/ucloud-sdk-go/services/uhost"
	"github.com/ucloud/ucloud-sdk-go/ucloud/request"
	"github.com/ucloud/ucloud-sdk-go/ucloud/response"
)
type (
	Backend interface {
		// standard uhost api
		CreateUHostInstance(*real.CreateUHostInstanceRequest) (*real.CreateUHostInstanceResponse, error)
		TerminateUHostInstance(*real.TerminateUHostInstanceRequest) (*real.TerminateUHostInstanceResponse, error)
		DescribeUHostInstance(*real.DescribeUHostInstanceRequest) (*real.DescribeUHostInstanceResponse, error)
		WaitUntilUHostInstanceState(*real.WaitUntilUHostInstanceStateRequest) error
		PoweroffUHostInstance(*real.PoweroffUHostInstanceRequest) (*real.PoweroffUHostInstanceResponse, error)
		StartUHostInstance(*real.StartUHostInstanceRequest) (*real.StartUHostInstanceResponse, error)
		StopUHostInstance(*real.StopUHostInstanceRequest) (*real.StopUHostInstanceResponse, error)
		RebootUHostInstance(*real.RebootUHostInstanceRequest) (*real.RebootUHostInstanceResponse, error)

	    // internal custom api
		MigrateUHostInstance(*MigrateUHostInstanceRequest) (*MigrateUHostInstanceResponse, error)
    }
)
```

Truman-Server 同时支持`ucloud-sdk-go`中的api调用形式(将参数通过query形式编码到http body中通过POST请求发送)，以及人类的友好 POST + JSON方式。



#### 后端存储

由于这是一个测试系统，对于可用性和可扩展性要求不高，因此后端存储使用了[bolt](https://github.com/boltdb/bolt)这样的文件KV存储框架，目前该框架已稳定并不在更新，新版本被CoreDNS所维护。

由于没有使用关系型数据库，因此对于诸如`Describe`接口的实现都是通过KV查找来完成，因此对于Describe请求，Truman-Server并没有完全实现所有filter参数的过滤能力。



#### 节点管理

Truman-Server通过调用Truman-Worker提供的API完成节点的创建、删除、迁移等操作，通过Truman-Worker屏蔽底层资源的差异性。



#### 资源类型



Sandbox节点为了和其他产品交互，如果绑定VIP、绑定EIP等，因此申请了真实的资源系统资源类型，并且创建、删除Sandbox节点的时候也会同步更新资源系统。



Sandbox产品的资源类型为：**284**，资源ID前缀为`tm-`。



### Truman-Gateway

Truman-Gateway提供了一个类似ssh网关的角色，它由一个ssh-server组成并监听在`2222`端口。Truman-Gateway会解析入向的ssh连接，并将其转发到正确的底层节点上。



ssh访问sandbox节点的方式如下，其中`tm-olzcbdcx`即为sandbox uhost的资源ID:

```bash
 ssh tm-olzcbdcx@sshgw.vpc.ucloudadmin.com -p 222
```

![](media/sandbox-3.png)



!> 为了维护测试环境，如果sandbox节点超过7天没有登录，则该资源会被自动释放。但我们更推荐你主动释放: )



#### 节点发现

Truman-Gateway并不会直接和Truman-Server交互来发现Sandbox节点的真实位置，为了屏蔽Sandbox细节，每个Sandbox的真实位置都被映射成一个唯一的DNS域名，Truman-Gateway通过域名解析即可完成Sandbox真实位置的查询。



对于上述示例来说，Truman-Gateway会使用如下域名来访问后端节点：

```
tm-olzcbdcx.gw.sandbox.vpc.ucloudadmin.com
```

![](media/sandbox-4.png)



#### 隔离



!> **注意：** 由于目前底层节点都是基于Namespace实现，因此在Sandbox节点中执行的任何命令都只会“网络隔离”，并会作用于真实宿主，因此操作时需要小心。



#### SET和集群



Truman-Server支持多集群管理，不同集群通常用于测试不同后端架构，如VPC2.0、VPC3.0等。因此创建Sandbox Uhost时可以指定SET ID和宿主机来创建，更多信息可以参考：[sandbox集群分布](http://doc.vpc.ucloudadmin.com/#/bible/%E9%A2%84%E5%8F%91%E5%B8%83UTest%E6%B5%8B%E8%AF%95%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97?id=%e9%a2%84%e5%8f%91%e5%b8%832%e5%a6%82%e4%bd%95%e8%bf%9b%e8%a1%8cvpc%e6%b5%8b%e8%af%95)。



### Truman-Worker

Truman-Worker负责Sandbox节点的生命周期管理，包括创建、销毁、重启、迁移等操作，目前仅实现了对于Namespace的支持。



> 一般来说Namespace足够VPC完成所有场景测试，因为namespace中有完整的、隔离的网络环境。

### 

### 工作流程

简化的工作流程示意如下：

- 用户通过Public API的方式创建Sandbox UHost（需要指定sandbox api url）；

- Truman-Server收到请求后会落盘到文件db中，并调用Truman-Worker完成Namespace的创建；

- Namespace创建成功后，Truman-Server会将Sandbox UHost的域名记录写入CoreDNS使用的Etcd中；

- 用户通过ssh访问Sandbox Uhost，该请求会到达Truman-Gateway；

- Truman-Gateway会通过dns解析查找Sandbox Uhost所在的真实Ip，并完成和后端ssh会话的建立和中转；

![](media/sandbox-2.png)

### 权限

Sandbox的API都有认证，因此只有授权后才可被调用和访问。



## 使用指南



### Sandbox API



**API域名：** http://api.sandbox.vpc.ucloudadmin.com

**方法：** POST

**Content-Type：** JSON



#### 创建Sandbox：CreateUHostInstance

```json
{
	"Action": "CreateUHostInstance",
	"ProjectId": "{{ Account }}",  // 项目ID，形式为 org-xxx
	"Region": "{{ Region  }}",     // Region名称，形式为pre2, pre, cn-bj2等
	"SubnetId": "{{ SubnetId }}",  // 子网ID
	"Tag": "vpc2.0_test",          // 标签，可选，Describe时可根据该Tag过滤
	"VPCId": "{{ VnetId }}",       // VPC ID
	"Zone": "{{ Zone  }}",         // 可用区名称，形式为pre2-01, pre, cn-bj2-05等
	"HostIp": "",                  // 指定宿主机创建，可选，默认为空即可
	"SetId": 2                     // 指定SET创建，可选，默认为0即可
}
```



Region名称和Zone名称可参见：[获取地域和可用区列表](https://docs.ucloud.cn/api/summary/regionlist)

目前Sandbox支持的地域请联系：try.chen获取。



response:

```json
{
  "Action": "CreateUHostInstance",
  "RetCode": 0,
  "Message": "awesome",
  "UHostIds": [
    "tm-gg1qmlcq"
  ],
  "IPs": [
    "192.168.1.95"
  ]
}
```



#### 释放Sandbox：TerminateUHostInstance

```json
{
	"Action": "TerminateUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostId": "tm-1oiw5tgz"
}
```

response:

```json
{
  "Action": "TerminateUHostInstance",
  "RetCode": 0,
  "Message": "",
  "InRecycle": "No",
  "UHostId": "tm-1oiw5tgz"
}
```



#### 展示Sandbox：DescribeUHostInstance

获取项目下的全部Sandbox Uhost：

```json
```json
{
	"Action": "DescribeUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}"
}
```
```



指定ID获取：

```json
{
	"Action": "DescribeUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostIds": [
		"tm-nrw30tg3"
	]
}
```



指定Tag获取：

```json
{
	"Action": "DescribeUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
    "Tag": "vpc2.0_test"
}
```



response:

```json
{
  "Action": "DescribeUHostInstance",
  "RetCode": 0,
  "Message": "awesome",
  "TotalCount": 1,
  "UHostSet": [
    {
      "Zone": "cn-gd-02",
      "UHostId": "tm-wrwugkle",
      "UHostType": "",
      "MachineType": "",
      "StorageType": "",
      "ImageId": "",
      "BasicImageId": "",
      "BasicImageName": "",
      "Tag": "",
      "Remark": "",
      "Name": "",
      "State": "Running",
      "CreateTime": 1602749034,
      "ChargeType": "",
      "ExpireTime": 1603353842,         // 该字段为Sandbox Uhost的过期时间
      "CPU": 1,
      "Memory": 1024,
      "AutoRenew": "Yes",
      "DiskSet": [],
      "IPSet": [
        {
          "Default": "",
          "Mac": "52:54:00:3C:1E:5E",
          "Weight": 0,
          "Type": "Private",
          "IPId": "",
          "IP": "192.168.1.10",
          "Bandwidth": 0,
          "VPCId": "uvnet-l3wyfypi",
          "SubnetId": "subnet-b2eia2ad"
        }
      ],
      "NetCapability": "",
      "NetworkState": "172.27.33.72",    // 该字段保存了宿主机IP
      "TimemachineFeature": "",
      "HotplugFeature": false,
      "SubnetType": "",
      "IPs": [
        "192.168.1.10"
      ],
      "OsName": "centos",
      "OsType": "Linux",
      "DeleteTime": 0,
      "HostType": "s2",
      "LifeCycle": "Normal",
      "GPU": 0,
      "BootDiskState": "Normal",
      "TotalDiskSpace": 0,
      "IsolationGroup": ""
    }
  ]
}
```



#### 开机Sandbox：StartUHostInstance

```json
{
	"Action": "StartUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostId": "tm-40kathr2"
}
```



> Sandbox Uhost默认创建后立刻就会处于Running状态，并可被访问，除非被手动Poweroff。



response:

```json
{
  "Action": "StartUHostInstance",
  "RetCode": 0,
  "Message": "awesome",
  "UhostId": "tm-40kathr2"
}
```

#### 关机Sandbox:  PoweroffUHostInstance

```json
{
	"Action": "PoweroffUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostId": "tm-40kathr2"
}
```



#### 重启Sandbox：RebootUHostInstance

```json
{
	"Action": "RebootUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostId": "tm-40kathr2"
}
```



#### 在Sandbox中执行命令：ExecuteUHostInstance（私有）

```json
{
	"Action": "ExecuteUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}",
	"UHostId": "tm-l45dzm40",
	"Cmd": "ip addr del 1.1.1.1/32 dev eth0"
}
```



response:

```json
{
  "Action": "ExecuteUHostInstance",
  "RetCode": 0,
  "Message": "awesome",
  "Stdout": "",
  "Stderr": "",
  "RC": 0
}
```



#### 迁移Sandbox：MigrateUHostInstance（私有）

```json
{
	"Action": "MigrateUHostInstance",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
    "UHostId": "tm-v4ws0ixj",
	"ToHost": "1.1.1.1",            // 目的宿主机，必填，必须支持truman-worker
    "MigrateMode": "",              // 可选，默认留空即可，迁移模式，解释如下
    "WaitTime":  0                  // 可选，默认为0即可，lock和unlock之间等待的秒数，用于flow同步等测试
}
```



此外，迁移模式支持如下参数：

| MigrateMode       | 场景               | 步骤                                                     |
| ----------------- | ---------------- | ------------------------------------------------------ |
| Standard          | 标准主机迁移流程         | lock -> add_port@toHost -> del_port@oldHost -> unlock  |
| Offline           | 离线迁移             | lock -> del_port@fromHost -> add_port@toHost -> unlock |
| DeleteAfterUnlock | UDB/UMEM等使用的迁移方式 | lock -> add_port@toHost -> unlock -> del_port@oldHost  |



#### DescribePublicDnsIps：获取用户网DNS IP（私有）

```json
{
	"Action": "DescribeDescribePublicDnsIps",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}"
}
```

#### 

#### DescribeSupportPrivateIp: 获取Suppot机器公共服务IP（私有）

```json
{
	"Action": "DescribeSupportPrivateIp",
	"ProjectId": "{{ Account }}",
	"Region": "{{ Region  }}",
	"Zone": "{{ Zone  }}"
}
```

response：

```json
{
  "Action": "DescribeSupportPrivateIp",
  "RetCode": 0,
  "Message": "",
  "Ip": "100.64.192.250",        // Support机器公共服务IP
  "Host": "10.64.68.141"         // Support机器管理IP
}
```

#### GetOrgInfoFromAlias: 使用项目别名获取项目信息（私有）

```json
{
	"Action": "GetOrgInfoFromAlias",
	"OrgAlias": "org-c5bxns",
	"RegionName": "pre2"
}
```

response:

```json
{
  "RetCode": 0,
  "Message": "",
  "OrganizationInfo": {
    "OrganizationId": 27,
    "OrganizationAlias": "org-c5bxns",
    "CompanyId": 25,
    "Name": "sandbox测试",
    "Created": 1597209947,
    "Updated": 1597209947,
    "ParentId": 0,
    "Deleted": 0,
    "Audited": 1
  }
}
```

#### LuckyGetOrgInfoFromAlias: 使用项目别名获取项目信息（私有）

```json
{
	"Action": "LuckyGetOrgInfoFromAlias",
	"OrgAlias": "org-c5bxns"
}
```

> LuckyGetOrgInfoFromAlias和GetOrgInfoFromAlias的区别在于不用传RegionName，LuckyGetOrgInfoFromAlias会尝试从online、pre2、pre分别去获取，直到查找成功。



---

> **Truman** 的命名来自于《楚门的世界》。


