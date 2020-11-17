# 基于kunapp的微服务开发实践

<p align="right"><font color=Grey>try.chen 2020-10-28</font></p>

## KUNAPP

[kunapp](https://git.ucloudadmin.com/vnpd/kunapp)是我们虚拟网络内部针对KUN上应用开发的一个服务框架，其前身是[uxr/app](https://gitlab.ucloudadmin.com/unet-uxr/app)，主要用于快速开发gRPC服务，并附带了一些gRPC、Istio和K8S的相关特性。目前VPC3几乎所有服务都是基于`kkunapp，借助于kunapp我们可以获得一些预定义好的服务能力。

### Get Started

kunapp中携带了一个example：[kunapp-echo](https://git.ucloudadmin.com/vnpd/kunapp/-/tree/master/examples/kunapp-echo)，可基于此了解kunapp框架。

### Kubernetes支持

kunapp在启动时会通过环境变量获取K8S的基础信息，包括 Domain、Namespace、Cluster、Service、Pod等。如我们会使用`Application.Instance`来获取Pod_Id作为服务的唯一标识。

同时kunapp还支持了K8S的探针机制，实现了基于HTTP的Liveness Probe和Readiness Probe，并提高了服务设置探针的方法，配合K8S可以实现服务的优雅退出和无损升级等。

> 其中，`LivenessProbe` 主要用作服务的存活性判断，`LivenessProbe`探测失败之后K8S会重启Pod来恢复服务；而`ReadinessProbe`主要用作服务的可用性判断，当服务不可用期间，K8S不会把流量和请求调度到探测失败的节点上。

对于`ReadinessProbe`的一个典型示例就是dpmgr启动时需要从上游拉取全量数据，而在数据不完全期间是不允许处理客户端请求的，否则可能会导致客户端数据破坏，因此`dpmgr`在服务启动后就会设置`ReadinessProbe`为dead，只有当全量数据拉取成功后，才会设置`ReadinessProbe`为alive。

通过使用探针的好处在于可以主动控制K8S的调度策略，使得尽量降低服务的异常带来的服务不可用。

实现：

```go
func (app *Application) Start() error {
    app.Info("starting application...")

    if app.AppConfig().AdminPort != 0 {
        if err := app.startAdminServer(); err != nil {
            return err
        }
    }

    if app.Grpc != nil {
        if err := app.startGRPCServer(); err != nil {
            return err
        }
    }

    if app.Http != nil {
        if err := app.startHTTPServer(); err != nil {
            return err
        }
    }

    // 默认在Start()时配置探针Alive，如果需要修改此行为，可在startCallbacks中修改
    app.Readiness.SetStatusAlive()

    for _, cb := range app.startCbs {
        if err := cb(); err != nil {
            return err
        }
    }

    return nil
}

func (app *Application) Stop() error {
    app.Readiness.SetStatusDead()
    app.cancel()

    if nil != app.admin {
        app.stopAdminServer()
    }

    if nil != app.Grpc {
        app.stopGrpc(app.Grpc)
    }

    if nil != app.Http {
        ctx, cancel := context.WithTimeout(context.TODO(), 3*time.Second)
        defer cancel()

        if err := app.Http.Shutdown(ctx); err != nil {
            app.Warn("failed to stop HTTP server.", zap.Error(err))
        }
        app.Info("HTTP server is stopped.")
    }

    for _, cb := range app.stopCbs {
        if err := cb(); err != nil {
            app.Warnf("callback stop error: %v", err)
        }
    }

    return nil
}
```

### Graceful Shutdown

为了实现K8S上POD的无损设计升级，我们首先需要了解K8S的滚动升级策略，建议阅读[Zero-Downtime Rolling Updates With Kubernetes](https://blog.sebastian-daschner.com/entries/zero-downtime-updates-kubernetes)。

当进行服务升级时，K8S首先会将新增流量不再调度到指定POD上，并向POD发送Signal Term，kunapp会捕获该信号，并尝试停止grpc Server，此时如果立刻停止可能会导致in-flight的请求由于未能完成处理从而造成服务中断，因此kunapp中对于gRPC Server采用了GracefulStop方法来保证unary api不中断。

!> 由于stream类型api可能始终无法退出，因此在GracefulStop失败时(超时)，会进行强制Stop。

实现：

```go
func (app *Application) stopGrpc(grpcServer *grpc.Server) {
    ctx, cancel := context.WithTimeout(context.Background(),
        time.Duration(app.AppConfig().GRPCServer.GrpcGracefulStopTimeout)*time.Second)
    defer cancel()

    // if GracefulStop block, the hard stop will done, and then the GracefulStop will continue
    stopped := make(chan interface{})
    go func() {
        grpcServer.GracefulStop()
        stopped <- struct{}{}
    }()

    select {
    case <-ctx.Done():
        grpcServer.Stop()
        app.Info("GRPC server graceful stop timeout, hard stopped")
        <-stopped // wait the GracefulStop goroutine exit
    case <-stopped:
        app.Info("GRPC server is graceful stopped")
    }
}
```

但对于非K8S应用，目前我们仍然没有成熟的优雅退出方案，可以考虑在kunapp框架中实现，一般的方案如：主进程收到Signal Term后fork一个子进程，并将socket fd复制给子进程，子进程负责处理新请求，老进程在in-flight请求处理完成后完成退出。

### 配置文件

kunapp支持多层级配置文件，配合K8S的概念包括Namespace、Service、Cluster、Instance级别，并且越明细越优先生效。其读取配置文件的目录位于：

| 级别        | 位置                                                     |
| --------- | ------------------------------------------------------ |
| Instance  | {Base}/conf/{Service}/{Cluster}/{Instance}/public.yaml |
| Cluster   | {Base}/conf/{Service}/{Cluster}/public.yaml            |
| Service   | {Base}/conf/{Service}/public.yaml                      |
| Namespace | {Base}/conf/public.yaml                                |

!> kunapp目前对于配置文件merge存在的一个问题在于对于bool变量的处理，由于bool的初始值为false，因此`kkunapp区分false是人为设置还是默认值，因此即使Instance配置显式指定false，也会被外层Namespace级别的true覆盖。

此外，kunapp也支持配置文件的变更监听，但业务层面是否支持配置动态生效就需要各自实现。

实现：

```go
func (c *Store) Fetch(ctx context.Context, cfg interface{}) error {
    if err := c.fetchConfig(ctx, c.name.InstanceKey(), true, cfg); err != nil {
        return err
    }

    if err := c.fetchConfig(ctx, c.name.ClusterKey(), true, cfg); err != nil {
        return err
    }

    if err := c.fetchConfig(ctx, c.name.ServiceKey(), false, cfg); err != nil {
        return err
    }

    if err := c.fetchConfig(ctx, c.name.ShareKey(), true, cfg); err != nil {
        return err
    }

    return nil
}
```

### gRPC拦截器

为了使的服务开发更简单易用，kunapp支持了多种gRPC拦截器并通过配置文件开启，主要包括：

- **Proxy：** 用于支持Envoy灰度；

- **OpenTracing：** 支持gRPC请求埋点；

- **Prometheus：** 支持暴露gRPC client/server相关metrics；

- **Logging:** 支持日志记录request/response详细内容和截断等;

- **KeepAlive:** 默认开启keepalive的支持；

对于普通gRPC服务推荐全都开启，一般典型kunapp的配置文件类似：

```yaml
GRPCDial:
  MaxMsgSize:        4294967296 # 配置为4G
  Timeout:           5          # gRPC Dial 5s超时
  Block:             true       # gRPC Dial为阻塞式拨号
  Insecure:          tru        # 始终填true，我们未实现SSL加密和证书
  WithProxyPort:     15003      # kun上该值始终填15003，为envoy的代理端口，kun下服务无此配置
  LoggingZap:        true       # 支持x-request-id注入和logger注入
  OpenTracing:       true       # 启用opentracing
  Prometheus:        true       # 启用Prometheus
  DisableKeepalive:  false      # 默认启用keepalive
  LoggingAllRpc:     false      # 可选是否开启记录request/response
  LoggingRpcMaxSize: 1024       # 记录request/response的最大字符长度

GRPCServer:
  MaxMsgSize:        4294967296 # 配置为4G
  Recovery:          true       # 对gRPC消息处理异常panc时进行recover
  Prometheus:        true       # 启用Prometheus
  OpenTracing:       true       # 启用opentracing
  CtxTags:           true       # 支持gRPC Context
  DisableKeepalive:  false      # 默认启用keepalive       
  LoggingZap:        true       # 支持x-request-id注入和logger注入
  LoggingAllRpc:     false      # 可选是否开启记录request/response
  LoggingRpcMaxSize: 1024       # 记录request/response的最大字符长度

Zipkin:
  Hosts:
    - jaeger.prj-vpc.svc.a2.uae # jaeger或zipkin配置

Logger:
  Level:          info
  Development:    false
  Prometheus:     true
```

> 对于kunapp使用的拦截器，我们自己实现了其中的日志记录(loggingAllRpc)，request-id注入和级联(loggingZap)，因此我们单独checkout了一个分支位于[go-grpc-middleware](https://git.ucloudadmin.com/vnpd/go-grpc-middleware)，其中的gRPC Context维护在该版本中。

### 灰度

kunapp框架中提供了一个函数`NewRouteByContext`用于将灰度的kv信息编码进`context.Context`中，在gRPC调用时通过携带该context，即可将kv信息填入gRPC metadata(http header)中，同时配合envoy即可完成基于metadata的灰度和路由控制。

实现：

```go
func (app *Application) NewRouteByContext(ctx context.Context, routes map[string]string) context.Context {
    return NewRouteByContext(ctx, routes)
}
```

示例：

```go
func (srv *Server) ReadCache(ctx context.Context, req *services.ReadCacheRequest) (*services.ReadCacheResponse, error) {
    ctx = srv.NewRouteByContext(ctx, map[string]string{"AccountId": req.GetAccountId())
    srv.upstream.Get(ctx, &proto.GetRequest{req.GetKey()})
    // ...
}
```

### gRPC RetCode

对于gRPC Api的RetCode建议按照google官方定义的gRPC  RetCode来返回，其定义在：[grpc-go/codes.go](https://github.com/grpc/grpc-go/blob/master/codes/codes.go)，其包含了常见返回

对于gRPC API的error应该按照google官方定义的Error Model来返回，其proto定义如下：

```protobuf
package google.rpc;

message Status {
  // A simple error code that can be easily handled by the client. The
  // actual error code is defined by `google.rpc.Code`.
  int32 code = 1;

  // A developer-facing human-readable error message in English. It should
  // both explain the error and offer an actionable resolution to it.
  string message = 2;

  // Additional error information that the client code can use to handle
  // the error, such as retry delay or a help link.
  repeated google.protobuf.Any details = 3;
}
```

*-- 引用自 [googleapis/status.proto](https://github.com/googleapis/googleapis/blob/master/google/rpc/status.proto)*

而Return Code，也可以使用google定义的Error Code，其proto定义如下：

```protobuf
package google.rpc;
enum Code {
  // Not an error; returned on success
  //
  // HTTP Mapping: 200 OK
  OK = 0;

  // The operation was cancelled, typically by the caller.
  //
  // HTTP Mapping: 499 Client Closed Request
  CANCELLED = 1;

  // Unknown error.  For example, this error may be returned when
  // a `Status` value received from another address space belongs to
  // an error space that is not known in this address space.  Also
  // errors raised by APIs that do not return enough error information
  // may be converted to this error.
  //
  // HTTP Mapping: 500 Internal Server Error
  UNKNOWN = 2;

  // The client specified an invalid argument.  Note that this differs
  // from `FAILED_PRECONDITION`.  `INVALID_ARGUMENT` indicates arguments
  // that are problematic regardless of the state of the system
  // (e.g., a malformed file name).
  //
  // HTTP Mapping: 400 Bad Request
  INVALID_ARGUMENT = 3;

  // The deadline expired before the operation could complete. For operations
  // that change the state of the system, this error may be returned
  // even if the operation has completed successfully.  For example, a
  // successful response from a server could have been delayed long
  // enough for the deadline to expire.
  //
  // HTTP Mapping: 504 Gateway Timeout
  DEADLINE_EXCEEDED = 4;

  // Some requested entity (e.g., file or directory) was not found.
  //
  // Note to server developers: if a request is denied for an entire class
  // of users, such as gradual feature rollout or undocumented whitelist,
  // `NOT_FOUND` may be used. If a request is denied for some users within
  // a class of users, such as user-based access control, `PERMISSION_DENIED`
  // must be used.
  //
  // HTTP Mapping: 404 Not Found
  NOT_FOUND = 5;

  // The entity that a client attempted to create (e.g., file or directory)
  // already exists.
  //
  // HTTP Mapping: 409 Conflict
  ALREADY_EXISTS = 6;

  // The caller does not have permission to execute the specified
  // operation. `PERMISSION_DENIED` must not be used for rejections
  // caused by exhausting some resource (use `RESOURCE_EXHAUSTED`
  // instead for those errors). `PERMISSION_DENIED` must not be
  // used if the caller can not be identified (use `UNAUTHENTICATED`
  // instead for those errors). This error code does not imply the
  // request is valid or the requested entity exists or satisfies
  // other pre-conditions.
  //
  // HTTP Mapping: 403 Forbidden
  PERMISSION_DENIED = 7;

  // The request does not have valid authentication credentials for the
  // operation.
  //
  // HTTP Mapping: 401 Unauthorized
  UNAUTHENTICATED = 16;

  // Some resource has been exhausted, perhaps a per-user quota, or
  // perhaps the entire file system is out of space.
  //
  // HTTP Mapping: 429 Too Many Requests
  RESOURCE_EXHAUSTED = 8;

  // The operation was rejected because the system is not in a state
  // required for the operation's execution.  For example, the directory
  // to be deleted is non-empty, an rmdir operation is applied to
  // a non-directory, etc.
  //
  // Service implementors can use the following guidelines to decide
  // between `FAILED_PRECONDITION`, `ABORTED`, and `UNAVAILABLE`:
  //  (a) Use `UNAVAILABLE` if the client can retry just the failing call.
  //  (b) Use `ABORTED` if the client should retry at a higher level
  //      (e.g., when a client-specified test-and-set fails, indicating the
  //      client should restart a read-modify-write sequence).
  //  (c) Use `FAILED_PRECONDITION` if the client should not retry until
  //      the system state has been explicitly fixed.  E.g., if an "rmdir"
  //      fails because the directory is non-empty, `FAILED_PRECONDITION`
  //      should be returned since the client should not retry unless
  //      the files are deleted from the directory.
  //
  // HTTP Mapping: 400 Bad Request
  FAILED_PRECONDITION = 9;

  // The operation was aborted, typically due to a concurrency issue such as
  // a sequencer check failure or transaction abort.
  //
  // See the guidelines above for deciding between `FAILED_PRECONDITION`,
  // `ABORTED`, and `UNAVAILABLE`.
  //
  // HTTP Mapping: 409 Conflict
  ABORTED = 10;

  // The operation was attempted past the valid range.  E.g., seeking or
  // reading past end-of-file.
  //
  // Unlike `INVALID_ARGUMENT`, this error indicates a problem that may
  // be fixed if the system state changes. For example, a 32-bit file
  // system will generate `INVALID_ARGUMENT` if asked to read at an
  // offset that is not in the range [0,2^32-1], but it will generate
  // `OUT_OF_RANGE` if asked to read from an offset past the current
  // file size.
  //
  // There is a fair bit of overlap between `FAILED_PRECONDITION` and
  // `OUT_OF_RANGE`.  We recommend using `OUT_OF_RANGE` (the more specific
  // error) when it applies so that callers who are iterating through
  // a space can easily look for an `OUT_OF_RANGE` error to detect when
  // they are done.
  //
  // HTTP Mapping: 400 Bad Request
  OUT_OF_RANGE = 11;

  // The operation is not implemented or is not supported/enabled in this
  // service.
  //
  // HTTP Mapping: 501 Not Implemented
  UNIMPLEMENTED = 12;

  // Internal errors.  This means that some invariants expected by the
  // underlying system have been broken.  This error code is reserved
  // for serious errors.
  //
  // HTTP Mapping: 500 Internal Server Error
  INTERNAL = 13;

  // The service is currently unavailable.  This is most likely a
  // transient condition, which can be corrected by retrying with
  // a backoff. Note that it is not always safe to retry
  // non-idempotent operations.
  //
  // See the guidelines above for deciding between `FAILED_PRECONDITION`,
  // `ABORTED`, and `UNAVAILABLE`.
  //
  // HTTP Mapping: 503 Service Unavailable
  UNAVAILABLE = 14;

  // Unrecoverable data loss or corruption.
  //
  // HTTP Mapping: 500 Internal Server Error
  DATA_LOSS = 15;
}
```

*-- 引用自[googleapis/code.proto](https://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto)*

对于gRPC Server来说，示例如下：

```go
import (
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)
func (srv *Server) ReadCache(ctx context.Context, req *services.ReadCacheRequest) (*services.ReadCacheResponse, error) {
    if req.GetKey() == "" {
        return nil, status.Errorf(codes.InvalidArgument, "unexpected key: %v", err)
    }
    value, err = srv.read(req.GetKey())
    if err != nil {
        return nil, status.Errorf(codes.Internal, "read error: %v", err)
    }
    // ...
}
```

关于error的其他信息可以参考google的 [API Design Guide](https://cloud.google.com/apis/design/errors).

### 重试

借助于envoy我们可以完成gRPC请求的简单重试，通过按照上述RetCode的定义来返回，我们便可控制对于预期的错误码进行重试。

envoy的重试配置类似于：

```yaml
retry_on: "5xx"
num_retries: 3
per_try_timeout_ms: 2000
```

对于gRPC 请求，则有：

| 参数                                     | 值                                                                |
| -------------------------------------- | ---------------------------------------------------------------- |
| x-envoy-retry-grpc-on                  | grpc status:<br/>cancelled<br/>deadline-exceeded<br/>unavailable |
| x-envoy-max-retries                    | 3                                                                |
| x-envoy-upstream-rq-per-try-timeout-ms | 5000                                                             |

> 据历史经验观察，重试三次以内可以解决85%的失败，因此此处配置为3次。

!> 对于envoy的重试我们也踩过不少坑，在stream类型的gRPC通信下，由于我们的使用场景中会始终不close stream当做长连接用，此时envoy会缓存全部的request/response，最终导致envoy oom。

同时我们也可以使用grpc-middleware中的重试拦截器，示例如下：

```go
import (
    "time"

    grpc_retry "github.com/grpc-ecosystem/go-grpc-middleware/retry"
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
)

func RetryOptions() []grpc.CallOption {
    return []grpc.CallOption{grpc_retry.WithMax(3),
        grpc_retry.WithCodes(codes.Internal, codes.Unavailable, codes.Canceled,
            codes.DeadlineExceeded, codes.ResourceExhausted, codes.Unknown),
        grpc_retry.WithBackoff(grpc_retry.BackoffExponential(time.Millisecond * 50))}
}


func example(svc ServiceClient) (uint64, error) {
    res, err := svc.EventService.BPub(ctx, &event.BPubEventRequest{
        Events: []*event.Event{copyev},
    }, util.RetryOptions()...)
    if err != nil {
        return 0, err
    }
}
```

关于重试的更多信息可以参考：[Retry pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/retry)，和[重试策略](https://ushare.ucloudadmin.com/pages/viewpage.action?pageId=34239756).

### gRPC API

对于普通CURD类型API我们都是使用的unary API，但存在如下几种情况会使用stream api：

- 服务端需要向客户端推送数据，但客户端列表变化频繁且数量巨大，此时我们采用的策略是客户端通过stream api连接到服务端，服务端会通过该stream来推送数据；

- 客户端需要watch在服务端监听变更等；

在使用stream api的时候由于stream不释放我们也遇到过如下问题，且部分问题尚无法解决：

- envoy无法灰度stream api；

- opentracing无法对于stream api完成打点；

- envoy对于stream api开启重试后导致oom；
