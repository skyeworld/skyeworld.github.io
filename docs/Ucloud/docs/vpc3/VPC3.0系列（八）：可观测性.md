# VPC3.0系列（八）：可观测性

<p align="right"><font color=Grey>try.chen 2020-06-18</font></p>

## 前言

VPC3.0是个高度分布式的系统，据不完全统计微服务数量达到30+，因此如何良好的观测整个系统是否工作工作，能否良好的维护决定了这套微服务系统是否可持续。

## 监控、告警、日志

由于VPC3.0都部署在了KUN上，因此KUN提供了较为完善的监控和日志能力，此处不再细说。

<img title="" src="media/vpc3-7-4.png" alt="" data-align="inline">

<img title="" src="media/vpc3-7-5.png" alt="" data-align="inline">

![](media/vpc3-7-6.png)

![](media/vpc3-7-7.png)

## 全链路x-request-id

对于一个多级调用系统来说，如下图，Service1 调用 Service2，Service2 调用 Service3，那我们自然希望Service1 首次调用的`request_id`, 可以一路被继承到调用链上的后续子服务中，这样通过一条贯穿的调用链，我们很容易在`ES`中根据最顶层`request_id`来检索调用链上的请求日志。

<img src="media/vpc3-7-1.png" title="" alt="" data-align="center">

因此，基于`kunapp`我们实现了一个全链路`x-request-id`，对于一个gRPC级联系统来说，只需要沿途传递`Context`，即会透传`x-request-id`。

使用时，只需要在service1 调用service2的context中初始化一个`x-request-id`即可，后续`kunapp`中的自定义拦截器会完成context的继承和传递，将incoming context传递到outgoing context。

### 会话级logger

在API处理handler中，我们往往希望打印的日志携带上述`x-request-id`请求调用信息，如果总是手动通过在函数间传递logger、再`WithField`那么总是不变的。

因此我们基于`kunapp`提供了gRPC会话级别的logger。在kunapp的自定义拦截器中，我们会初始化一个logger并嵌入`x-request-id`信息，同时把这个logger放入gRPC Context中，后续业务层使用时，只需要从context中弹出logger即可。对于logger也不需要显式传递，而是传递context即可。

### gRPC request/response日志

对于gRPC调用的Request和Response打印我们同样实现了一个自定义拦截器，用于在框架层打印所有的request、response日志，除了官方提供的功能，我们还做了如下改造：

- 打印request/response时使用前文提到的会话级logger，因此日志中携带有`x-request-id`信息；

- 打印request/response时支持设置MaxLen，防止某些message body过长带来的日志问题；

## 全链路OpenTracing

![](media/vpc3-7-3.png)

VPC3.0的调用栈非常深，因此我们基于`jaeger`建立了一套`OpenTracing`系统，用于快速发现调用栈的处理情况和耗时等。关于`OpenTracing`的细节我们介绍，仅介绍我们在其中做的定制和实现。

由于gRPC生态里已有完善的`OpenTracing`拦截器的实现，可以无倾入的实现Tracing的集成，但我们在VPC3.0的实现中还是遇到了以下几个问题。

### MQ穿透

从前文可知，event-service事件的发布会经过MQ传递，而Resource-Service对于对象在集群间扩散同样会经过MQ。而默认的SpanContext信息（主要包含spanId, traceId等等）是注入在gRPC的metadata（http header）中，因此经过MQ时，会导致trace信息中断，从而调用链在两个MQ出发生中断。

因此针对如上问题，我们会在`Event`以及`Resource`等对象的定义中嵌入了一个`map[string]string`定义的`SpanContext`字段。

从而在入MQ时，我们会将SpanContext序列化到map中，同时注入入队列的timestamp，而下游从MQ收到该事件后，会从map反序列化出SpanContext，构造出Span后再Finish这次Span，同时嵌入MQ排队耗时时间戳。

### gRPC Stream穿透

对于gRPC生态里提供的OpenTracing拦截器来说，会在一次stream request调用完去`FinshSpan`，而由于我们的诸多调用，如DPAgent 长连接watch在DPMgr上，DPMgr长连接watch在Resource-Service上，这些stream是永远不会中断的，也就造成了默认拦截器里的Span永远无法结束，从而stream类型的trace无法生效。

对于这个问题，我们也是类似的解法，在Stream信道中传递的`BridgeObject`对象和`Resource`对象中都定义了`map[string]string`定义的`SpanContext`字段。

## 服务探针

我们会有一些probe节点去监听MQ的所有topic，以及Resource-Service的所有对象，以此来探测系统中的MQ、RS是否工作符合预期，在某些事件出现延迟时，可以通过探针节点收到事件的情况来判断上下游的工作情况。
