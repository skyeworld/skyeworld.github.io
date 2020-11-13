# River: Flow分析系统

---

> - v1.0        2018-12-22      tyr.chen  初稿
> 
> - v1.1        2018-12-28      tyr.chen  api: pair支持参数nw_dst
> 
> - v1.2        2019-01-21      tyr.chen  api: 支持sign; 支持sdngw、cloudgw
> 
> - v1.3        2019-01-25      tyr.chen  api: 新增query api
> 
> - v1.4        2019-02-22      tyr.chen  api: 新增task-info, status
> 
> - v1.5        2019-09-07      tyr.chen  api: 新增collections, index
> 
> - v1.6        2020-01-30      tyr.chen  新增redis cache以及pre-refresh

## 简述

River系统的设计初衷是为了实现如下几个功能：

- 提供基于子网、VPC、用户等粒度的活跃flow分析功能，通过拉取最近7天内的活跃flow通信对端，作为BigBrother的检测来源；
- 提供基于pps、bps的flow流量统计和分析；
- 提供全网flow的结构化存储、搜索、获取flow的changelog等功能。

## Demo

<img title="" src="media/river-demo-1.png" alt="" data-align="center">



---



<img title="" src="media/river-demo-2.png" alt="" data-align="center">

## 概念

### Flow 签名

River 通过一个唯一索引标识现网任意一条flow：

- **host:** 即宿主机的管理网IP，标识flow的位置信息；
- **signature:** flow签名唯一标识一条flow，由flow的不变字段（去除duration、npackets、nbytes等统计信息）通过MD5哈希出一个固定长度的签名。

River在内部存储、索引和搜索时都通过该唯一索引确定一条结构化的flow。

除`host`和`signature`之外，River还定义了`msignature`，只是因为`signature`是根据flow的match和action计算出，但`msignature`只根据flow match中的不可变信息计算出的签名。

### 工作原理

1. River的采集目标（target）来自`t_ovs_info`，并向其USDNAgent port发送dump_flow_request；
2. River的采集周期为一天，每天会为该地域内的flow建立全量统计信息和结构化信息；
3. River会对每一条flow进行结构化、计算签名、获取overlay和underlay信息，并将flow的结构化信息保存为meta集合，将统计信息保存到stats集合；
4. meta集合默认三天超时，在超时期内会根据flow的duration增量更新到meta集合中，超时后会rebuild，以此保持和现网flow的同步；
5. stats集合默认保存15天的记录，超过15天的记录会自动清理；
6. 活跃flow保存在diff集合中，是通过分析当前最新的stats集合和7天前的stats集合来得出活跃flow。依据的指标有：flow生存时长、nbytes、npackets等。并以此计算出平均BPS和PPS；
7. 在活跃pair（通信源目）分析中，是根据match和action中的 dl_dst 作为目的mac，以此构建出源目的信息；
8. 如果启用了redis，River会将mac级别的活跃信息缓存在redis中（默认7天过期），并在构建完后自动刷新缓存。当查询VM活跃信息时（主要来自BB），将优先从Redis中获取缓存的Flow，以此优化构建时MongoDB查询慢的问题；

## 数据结构设计

目前River使用MongoDB作为存储后端，定义和使用了如何集合。

### meta

meta即为flow的结构化信息，meta中document的定义为：

```json
{
    "_id": ObjectId("5c1b962cbf3d231c6d8afe3e"),
    "sf": {
        "match": {
            "cookie": NumberLong("0"),
            "table": NumberLong("0"),
            "priority": NumberLong("60035"),
            "in_port": NumberLong("1"),
            "npackets": NumberLong("44017411"),
            "nbytes": NumberLong("11141049988"),
            "duration": 611189.267,
            "dl_src": "52:82:01:11:ff:7d",
            "dl_dst": "fa:ff:ff:ff:ff:ff"
        },
        "action": {
            "tun_id": NumberLong("18041206"),
            "dl_dst": "52:54:00:f7:23:11",
            "tun_dst": "172.28.178.11",
            "output": NumberLong("64200")
        }
    },
    "raw": "cookie=0x0, duration=611189.267s, table=0, n_packets=44017411, n_bytes=11141049988, priority=60035,ipv6,in_port=1,dl_src=52:82:01:11:ff:7d,dl_dst=fa:ff:ff:ff:ff:ff,ipv6_dst=2003:da8:2004:1000:a64:25:113:4976 actions=load:0x1134976->NXM_NX_REG0[],push_vlan:0x8100,set_field:52:54:00:f7:23:11->eth_dst,load:0xac1cb20b->NXM_NX_REG1[],set_field:0x100->metadata,load:0xfac8->NXM_NX_REG2[],resubmit(,100)",
    "signature": "fed7011b38a149badd818e925d3d5957",
    "msignature": "962ac0c0ebf5e57d966433332f907be2",
    "host": "172.27.174.235",
    "hostnode": {
        "cmdb": {
            "first": "ufs",
            "second": "unas",
            "azname": "cn-bj2-02"
        },
        "host": "172.27.174.235"
    },
    "src": {
        "ip": "10.42.255.125",
        "mac": "52:82:01:11:ff:7d",
        "subnet": "subnet-j4hjqt",
        "vpc": "uvnet-ilotav",
        "account": NumberLong("2344"),
        "type": NumberLong("2147483647"),
        "tun_id": NumberLong("15768348")
    },
    "dst": {
        "ip": "10.100.0.37",
        "mac": "52:54:00:f7:23:11",
        "subnet": "subnet-a42gc5",
        "vpc": "uvnet-orywp1",
        "account": NumberLong("20277"),
        "type": NumberLong("0"),
        "tun_id": NumberLong("18041206")
    },
    "type": NumberLong("0")
}
```

### stats

stats集合的命名格式为`stats-2018-12-21`这种格式，第一部分为前缀固定不变，第二部分为每天的日期。

stats集合中的文档定义为:

```json
{
    "_id": ObjectId("5c1c9aab6e58f6f72c7b0714"),
    "signature": "7644bebb08b08541246d7c2ec56f9281",
    "msignature": "9203a436202ec57d647ddd1746d87d56",
    "host": "172.28.173.104",
    "timestamp": "2018-12-19 17:16:17", // flow下发时间
    "npackets": NumberLong("58775"),
    "nbytes": NumberLong("3528454"),
    "duration": 167498.863
}
```

### diff

diff集合保存了最近的活跃flow，目前只分析最近七天的情况，因为实际集合名为**diff-7**。

diff集合中的文档定义为:

```json
{
    "_id": ObjectId("5c1bb5fabf3d231c6dadf721"),
    "host": "172.27.175.146",
    "signature": "3d557124f6e771d2dc7829bee90f077c",
    "nbytes": NumberLong("217134179015777"),
    "npackets": NumberLong("101394928426"),
    "bps": NumberLong("418854511"),
    "pps": NumberLong("195592"),
    "pretty_bps": "399.5 MB/s",
    "meta": {
    // 相关flow的meta信息，从meta集合中内嵌到这里，加快检索速度
    }
}
```

### info

info集合中目前主要保存任务的相关信息，包括meta集合的build时间和最新一次采样时间。

info集合的文档定义如下：

```json
{
    "_id": ObjectId("5c1ba5a468e26a7e13494fb1"),
    "timestamp": {
        // 最新采样时间 UTC
        "sample": ISODate("2018-12-21T07:47:49.515Z"),
        // 最新build meta时间 UTC
        "build": ISODate("2018-12-20T13:16:14.857Z")
    },
    "type": "time_meta"
}
```

## 部署

### 依赖

River依赖本地部署（为了访问更快）的MongoDB和Redis，无其他依赖。
River可通过docker部署，也可直接以二进制的方式部署。

### MongoDB部署

MongoDB 选用最新版本即可，在启动MongoDB前需要做以下优化。

```bash
ulimit -u 5000000
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# 对于物理机，禁用numa
numactl --interleave=all mongod --logpath /var/log/mongod.log --bind_ip_all --pidfilepath /var/run/mongo.pid &

# 对于虚机
mongod --logpath /var/log/mongod.log --bind_ip_all --pidfilepath /var/run/mongo.pid
```

对于MongoDB需要添加prometheus监控。

### River部署

从`http://192.168.152.143:8000/river/latest/river`获取到最新版本后，通过如下方式运行:

```bash
./river -r <region_id> -imm -log /var/log/river.log

# 如 ./river -r 1000001 -imm -log /var/log/river.log
```

river 默认绑定在0.0.0.0:8008端口，用于提供API、pprof和prometheus监控，可通过`-b`来修改。

目前River支持如下参数

| 参数    | 含义              | 默认值                 |
| ----- | --------------- | ------------------- |
| -a    | 只扫描指定项目，调试用     | null                |
| -b    | web server的监听地址 | 0.0.0.0:8008        |
| -c    | MongoDB并发写入连接   | 10                  |
| -dc   | dump-flow并发连接   | 10                  |
| -i    | 扫描间隔，单位为秒       | 86400               |
| -imm  | 运行后立刻构建         | false               |
| -l    | 缓冲队列长度          | 10                  |
| -log  | 日志位置            | river.log           |
| -r    | 地域RegionID      | 666888              |
| -u    | MongoDB URI     | mongodb://localhost |
| -warn | warn以上的日志发送到告警  | true                |

### 日志

River使用的日志框架集成了logrotated，包括压缩、自动清理，因此不需要再额外配置。

### 告警

River默认会将warn级别以上的日志通过SRE-Notify发送到企业微信，用于获取服务异常状态。

### 监控

River会在`0.0.0.0:8008/metrics`暴露prometheus的监控指标，目前提供如下监控：

| 指标                          | 枚举值                 | 含义                                                           | 类型  |
| --------------------------- | ------------------- | ------------------------------------------------------------ | --- |
| Go默认指标                      | -                   | Go默认监控指标                                                     | -   |
| river_collection_count      | -                   | MongoDB中集合的数量                                                | 瞬时值 |
| river_collection_statistics | diff meta stats     | 标识各个集合的文档数量； 此外还有如下标识：diff: 活跃flow数量 stats: 每天采集的flow总量      | 瞬时值 |
| river_meta_new_inserted     | -                   | 每天meta的新增flow数量，标识每天的新增flow数量                                | 瞬时值 |
| river_service_duration      | build diff          | 标识扫描、diff所需耗时                                                | 瞬时值 |
| river_service_timestamp     | diff sample startup | unix时间戳，sample: 上次扫描的时间点，diff: 上次构建diff的时间点，startup: 程序启动时间点 | 瞬时值 |

## API设计

目前River提供HTTP API的支持。

接入地址为 Mafia-**地域分发网关**。

API Response 统一为`application/json`，结构如下:

**正常响应**

```json
{
    "RetCode": 0,
    "Count": 200,
    "TotalCount": 2216605,
    "DataSet": [
    // ....
    ]
}
```

其中，Count 标识此次返回的DataSet数量，TotalCount 为总共数量，于 offset 和 limit 配合使用。

**异常响应**

对于服务端错误，会返回HTTP状态码503和body中的消息，标识错误原因。
对于输入参数错误，会返回如下响应：

```json
{
    "RetCode": 100,
    "Message": "invalid account: 2aaaa",
    "Count": 0,
    "TotalCount": 0,
    "DataSet": null
}
```

### Pair: 获取活跃通信对端

**Method: GET**

```
/pair
```

参数

| 参数      | 含义                     | 默认值  |
| ------- | ---------------------- | ---- |
| mac     | 指定mac                  | -    |
| subnet  | 指定子网ID                 | -    |
| vpc     | 指定VPC                  | -    |
| account | 指定项目ID                 | -    |
| offset  | 偏移                     | 0    |
| limit   | 一次返回个数                 | 200  |
| nw_dst  | 指定nw_dst               | -    |
| scalar  | 是否忽略src/dst方向，若true则去重 | true |

Request示例:

```
http://172.27.195.101:8008/river/api/pair?account=2344&offset=10000&limit=200
```

Response示例:

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 2234634,
    "DataSet": [
        {
            "src": {
                "ip": "10.10.252.159",
                "mac": "52:60:01:10:fe:9f",
                "subnet": "ada9cfcd-d971-43fc-becd-15502dd31f75",
                "vpc": "uvnet-ilotav",
                "account": 2344,
                "type": 2147483647,
                "tun_id": 15768348
            },
            "dst": {
                "ip": "10.19.122.161",
                "mac": "52:54:00:37:00:5f",
                "subnet": "subnet-yqahs2",
                "vpc": "uvnet-ww51ex",
                "account": 4519,
                "type": 0,
                "tun_id": 6202504
            }
        }
    ]
}
```

其中，如果指定`nw_dst`，则标识获取给定scope(mac|sub|vpc|account)去往这个**nw_dst**的活跃源。**nw_dst**必须和flow match中的**nw_dst**相匹配，如 ip或者网段（如托管云）。

默认设置scalar为true，意味着

```
src: 52:54:00:11:22:33
dst: 52:54:00:AA:BB:CC
```

和

```
src: 52:54:00:AA:BB:CC
dst: 52:54:00:11:22:33
```

是一致的，Response中的DataSet会做去重处理。

### Active-flow: 获取活跃flow

**Method: GET**

```
/active-flow
```

参数

| 参数      | 含义           | 默认值   |
| ------- | ------------ | ----- |
| mac     | 指定mac        | -     |
| subnet  | 指定子网ID       | -     |
| vpc     | 指定VPC        | -     |
| account | 指定项目ID       | -     |
| offset  | 偏移           | 0     |
| limit   | 一次返回个数       | 200   |
| detail  | 是否返回flow详细信息 | false |

Request示例

```
http://172.27.195.101:8008/river/api/active-flow?subnet=subnet-35bj1c
```

Response示例

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 321988,
    "DataSet": [
        {
            "host": "172.23.132.177",
            "signature": "76907b8d159460ac5eda283703a7d971",
            "bps": 1173367,
            "pps": 1054,
            "pretty_bps": "1.1 MB/s"
        }
    ]
}
```

如果指定`detail=true`，则返回如下Response:

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 321988,
    "DataSet": [
        {
            "host": "172.23.132.177",
            "signature": "76907b8d159460ac5eda283703a7d971",
            "bps": 1173367,
            "pps": 1054,
            "pretty_bps": "1.1 MB/s",
            "detail": {
                "sf": {
                    "match": {
                        "cookie": 0,
                        "table": 0,
                        "priority": 60000,
                        "in_port": 64200,
                        "npackets": 49028104393,
                        "nbytes": 54349226509648,
                        "duration": 50911418.032,
                        "tun_id": 12007598,
                        "dl_src": "52:54:00:cd:8a:fe",
                        "dl_dst": "52:54:00:64:68:20"
                    },
                    "action": {
                        "output": 1039
                    }
                },
                "raw": "cookie=0x0, duration=50911418.032s, table=0, n_packets=49028104393, n_bytes=54349226509648, priority=60000,tun_id=0xb738ae,in_port=64200,dl_src=52:54:00:cd:8a:fe,dl_dst=52:54:00:64:68:20 actions=output:1039",
                "signature": "76907b8d159460ac5eda283703a7d971",
                "msignature": "3f5bd13a1d2a69cf23edbfbb6304edfc",
                "host": "172.23.132.177",
                "hostnode": {
                    "cmdb": {
                        "first": "uhost",
                        "second": "uhost",
                        "azname": "cn-bj2-03"
                    },
                    "host": "172.23.132.177"
                },
                "src": {
                    "ip": "10.10.243.235",
                    "mac": "52:54:00:cd:8a:fe",
                    "subnet": "subnet-35bj1c",
                    "vpc": "uvnet-odifnp",
                    "account": 50017724,
                    "type": 0,
                    "tun_id": 12007598
                },
                "dst": {
                    "ip": "10.10.220.216",
                    "mac": "52:54:00:64:68:20",
                    "subnet": "subnet-35bj1c",
                    "vpc": "uvnet-odifnp",
                    "account": 50017724,
                    "type": 0,
                    "tun_id": 12007598
                },
                "type": 0
            }
        }
    ]
}
```

### Top-traffic: 获取TopN流量的flow

**Method: GET**

```
/top-traffic
```

参数

| 参数     | 含义                  | 默认值   |
| ------ | ------------------- | ----- |
| count  | TopN数量              | 10    |
| flow   | 是否返回flow信息（flow字符串） | false |
| cookie | 是否按照cookie过滤        | 不按照   |

Request示例

```
http://172.27.195.101:8008/river/api/top-traffic?count=20&flow=true
```

Response示例

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 1,
    "DataSet": [
        {
            "host": "172.27.175.146",
            "signature": "aa94bbc4023fb53cfa2ad6bc05ed0cf3",
            "nbytes": 11369988217703659,
            "npackets": 23218270566701,
            "bps": 18799583693,
            "pps": 38389997,
            "pretty_bps": "17.5 GB/s",
            // 如果指定flow=true，则返回raw字段，flow字符串
            "raw": "cookie=0x20004, duration=607451.820s, table=1, n_packets=28403952061671, n_bytes=14300149544974624, priority=0,metadata=0x1 actions=set_field:0x2->metadata,resubmit(,0)"
        }
    ]
}
```

其中，如果希望按照cookie过滤，则需要设置如:

```
http://172.27.195.101:8008/river/api/top-traffic?count=20&flow=true&cookie=0x80
```

默认不过滤，也无需设置cookie参数。

### flow：获取flow详细信息

**Method: GET**

```
/flow
```

参数

| 参数   | 含义     | 默认值 |
| ---- | ------ | --- |
| host | 宿主机IP  | -   |
| sign | flow签名 | -   |

Request示例

```
http://172.27.5.38:8008/river/api/flow?host=172.27.69.4&sign=109d8bbc77d9dbb8b5850720cd9f3570
```

Response示例

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 1,
    "DataSet": [
        {
            "sf": {
                "match": {
                    "cookie": 0,
                    "table": 0,
                    "priority": 60035,
                    "in_port": 89,
                    "npackets": 258651123,
                    "nbytes": 49300737583,
                    "duration": 4919938.369,
                    "dl_src": "52:54:00:1f:24:4c",
                    "dl_dst": "fa:ff:ff:ff:ff:ff",
                    "nw_dst": "10.13.46.116"
                },
                "action": {
                    "tun_id": 11594909,
                    "dl_dst": "52:54:00:1c:22:76",
                    "tun_dst": "172.27.36.154",
                    "output": 64200
                }
            },
            "raw": "cookie=0x0, duration=4919938.369s, table=0, n_packets=258651123, n_bytes=49300737583, priority=60035,ip,in_port=89,dl_src=52:54:00:1f:24:4c,dl_dst=fa:ff:ff:ff:ff:ff,nw_dst=10.13.46.116 actions=load:0xb0ec9d->NXM_NX_REG0[],set_field:52:54:00:1c:22:76->eth_dst,load:0xac1b249a->NXM_NX_REG1[],set_field:0x100->metadata,load:0xfac8->NXM_NX_REG2[],resubmit(,100)",
            "signature": "109d8bbc77d9dbb8b5850720cd9f3570",
            "msignature": "1a71d5aa1d830eec7bfa05f69011c301",
            "host": "172.27.69.4",
            "hostnode": {
                "cmdb": {
                    "first": "unet",
                    "second": "IGW",
                    "azname": "cn-gd-02"
                },
                "host": "172.27.69.4"
            },
            "src": {
                "ip": "",
                "mac": "52:54:00:1f:24:4c",
                "subnet": "subnet-r0aq3o",
                "vpc": "uvnet-boym4o",
                "account": 50184504,
                "type": 24,
                "tun_id": 11594909
            },
            "dst": {
                "ip": "10.13.46.116",
                "mac": "52:54:00:1c:22:76",
                "subnet": "subnet-r0aq3o",
                "vpc": "uvnet-boym4o",
                "account": 50184504,
                "type": 0,
                "tun_id": 11594909
            },
            "type": 0
        }
    ]
}
```

### Sign: 计算flow签名

**Method: GET**

```
/sign
```

参数

| 参数   | 含义      | 默认值 |
| ---- | ------- | --- |
| flow | flow字符串 | -   |

Request示例

```
http://127.0.0.1:8008/river/api/sign?flow=cookie=0x22101, duration=15103911.085s, table=0, n_packets=0, n_bytes=0, priority=59999,ip,tun_id=0x1011344,in_port=18778,nw_src=192.168.82.75,nw_dst=192.168.80.0/24 actions=set_queue:32145,set_field:0x1011344->tun_id,set_field:52:53:00:ff:0a:f0->eth_dst,set_field:52:53:00:00:00:01->eth_src,dec_ttl,output:9832
```

Response示例

```json
{
    "RetCode": 0,
    "Count": 1,
    "TotalCount": 1,
    "DataSet": [
        {
            "signature": "f168af54ea14254ded41af13f5000a1f",
            "msignature": "ff49acc881bf37cbe55e0485b8983cdd",
            "flow": "cookie=0x22101, duration=15103911.085s, table=0, n_packets=0, n_bytes=0, priority=59999,ip,tun_id=0x1011344,in_port=18778,nw_src=192.168.82.75,nw_dst=192.168.80.0/24 actions=set_queue:32145,set_field:0x1011344->tun_id,set_field:52:53:00:ff:0a:f0->eth_dst,set_field:52:53:00:00:00:01->eth_src,dec_ttl,output:9832"
        }
    ]
}
```

### Changelog: 获取flow变化信息

**Method: GET**

```
/changelog
```

参数

| 参数      | 含义                                 | 默认值   |
| ------- | ---------------------------------- | ----- |
| host    | 宿主机IP                              | -     |
| sign    | flow签名                             | -     |
| msign   | flow msign签名                       | -     |
| days    | 返回多少天的历史记录，最多15天                   | 15    |
| only-ts | 只返回flow下发时间变化的记录，忽略nbytes和npackets | false |

其中，必须输入`host`, `sign`和`msign`可选其一，不可同时输入。

Request示例

```
http://172.27.5.38:8008/river/api/changelog?host=172.27.32.209&sign=66131bec2747654fce5d5aff62c750a6&days=2
```

Response示例

```json
{
    "RetCode": 0,
    "Count": 2,
    "TotalCount": 2,
    "DataSet": [
        {
            "timestamp": "2018-12-18 06:02:50",
            "npackets": 115841018788,
            "nbytes": 154650984428760,
            "collection": "stats-2018-12-21"
        },
        {
            "timestamp": "2018-12-18 06:02:49",
            "npackets": 115525562321,
            "nbytes": 154241512905563,
            "collection": "stats-2018-12-20"
        }
    ]
}
```

当设置`only-ts`为true时，会按照flow下发时间过滤(允许10s的误差)，最终只返回下发时间不同的flow记录。

### query

`query` 用于查询后端MongoDB中的数据集，目前只支持简单的`and`和`or`，不支持更复杂的逻辑。

**Method: POST**

```
/query
```

参数如下：

```json
{
    # MongoDB collection
    "collection": "meta",

    # 查询输出的字段，逗号分隔
    "project": "raw,host",

    # 可不填，默认为and，另支持or
    "logic": "and",

    # offset limit
    # 暂不支持分页，因为不会返回TotalCount
    "limit": 1000,

    # 其余的所有字段视为filter
    "sf.match.proto": "ipv6",
    "sf.action.tun_id": 50702835
}
```

Response实例:

```json
{
    "RetCode": 0,
    "Count": 14,
    "TotalCount": 14,
    "DataSet": [
        {
            "host": "172.27.5.216",
            "raw": "cookie=0x0, duration=3136256.877s, table=0, n_packets=529, n_bytes=87396, priority=60000,ipv6,in_port=12,dl_src=52:63:00:2f:ec:ea,dl_dst=fa:ff:ff:ff:ff:ff,ipv6_dst=2003:da8:2004:1000:a64:1502:305:a9f3 actions=load:0x305a9f3->NXM_NX_REG0[],push_vlan:0x8100,set_field:52:53:00:00:00:02->eth_dst,load:0xac1b0602->NXM_NX_REG1[],set_field:0x100->metadata,load:0xfac8->NXM_NX_REG2[],resubmit(,100)"
        }
     ]
}
```

其中`DataSet`中的输出由Request中的`project`指定。

### task-info

`task-info` 用于查询上次flow扫描、构建的时间信息。

**Method: GET**

```
/task-info
```

请求示例:

```
http://172.27.195.101:8008/river/api/task-info
```

响应示例:

```json
{
    "RetCode": 0,
    "TSInfo": {
        "sample": "2019-02-21T17:53:27.436+08:00", # 上次全量flow扫描时间
        "build": "2019-02-19T17:53:27.949+08:00"   # 上次全量构建meta集合的时间
    }
}
```

### status

`status` 用于返回当前River的状态信息。

**Method: GET**

```
/status
```

请求示例:

```
http://172.27.195.101:8008/river/api/status
```

响应示例：

```json
{
    "RetCode": 0,
    "status": "Idle"
}
```

其中，status有以下三种状态:

| status    | 含义                    | 备注          |
| --------- | --------------------- | ----------- |
| FlowDump  | River当前正在扫描、结构化现网flow | 此时无法升级River |
| BuildDiff | River当前正在构建活跃flow     | 此时无法升级River |
| Idle      | 除上述之外的其他状态，标识当前空闲     | 可升级River    |

### collections

`collections` 用于获取当前 MongoDB 中的 collection（集合，类似于 MySQL 中的database）。

**Method: GET**

```
/collections
```

请求示例:

```
http://172.27.195.101:8008/river/api/collections
```

响应示例:

```json
{
    "RetCode": 0,
    "Count": 23,
    "TotalCount": 23,
    "DataSet": [
        "backup_meta-2019-08-24",
        "backup_meta-2019-08-28",
        "backup_meta-2019-09-01",
        "backup_meta-2019-09-05",
        "diff-7",
        "info",
        "meta",
        "stats-2019-08-31",
        "stats-2019-09-01",
        "stats-2019-09-02",
        "stats-2019-09-03",
        "stats-2019-09-04",
        "stats-2019-09-05",
        "stats-2019-09-06",
        "stats-2019-09-07"
    ]
}
```

### index

**Method: GET**

```
/index
```

参数

| 参数         | 含义   | 默认值 |
| ---------- | ---- | --- |
| collection | 集合名称 | 无   |

请求示例:

```
http://172.27.195.101:8008/river/api/index
```

响应示例:

```json
{
    "RetCode": 0,
    "Count": 14,
    "TotalCount": 14,
    "DataSet": [
        "dst.account",
        "dst.mac",
        "dst.subnet",
        "dst.type",
        "dst.vpc",
        "host",
        "hostnode.cmdb.first",
        "hostnode.cmdb.second",
        "signature",
        "src.account",
        "src.mac",
        "src.subnet",
        "src.type",
        "src.vpc"
    ]
}
```

## 其他

### River的 URI Handler

目前River监听在如下URI上:

```
GET    /debug/pprof/block
GET    /debug/pprof/heap
GET    /debug/pprof/profile
POST   /debug/pprof/symbol
GET    /debug/pprof/symbol
GET    /debug/pprof/trace
GET    /metrics
GET    /river/api/pair
GET    /river/api/active-flow
GET    /river/api/top-traffic
GET    /river/api/flow
GET    /river/api/changelog
```

### TODO

目前flow的结构化搜索只能在后端MongoDB中进行，使用MongoDB Extend JSON语法。

* [ ] 考虑导入elasticsearch，通过ES的DSL完成复杂查询和搜索
* [ ] 或者提供API，后台将查询逻辑转为MongoDB的DSL

### 项目及地址

[River: vpc/river](https://gitlab.ucloudadmin.com/vpc/river)

依赖如下项目：

[Base: vpc/base/flow 提供flow序列化](https://gitlab.ucloudadmin.com/vpc/base) 

[Fdump: vpc/fdump 提供flow dump](https://gitlab.ucloudadmin.com/vpc/fdump)
