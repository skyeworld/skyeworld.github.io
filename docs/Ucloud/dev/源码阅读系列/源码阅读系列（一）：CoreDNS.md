# 源码阅读系列（一）：CoreDNS

<p align="right"><font color=Grey>try.chen 2020-11-01</font></p>

## CoreDNS介绍

[CoreDNS](https://coredns.io/) 是一个灵活可扩展的 DNS 服务器，作为CNCF中托管的一个域名发现的项目，原生集成Kubernetes，它的目标是成为云原生的DNS服务器和服务发现的参考解决方案。从Kubernetes 1.12开始，CoreDNS就成了Kubernetes的默认DNS服务器。

之前在设计[Sandbox沙盒系统](http://doc.vpc.ucloudadmin.com/#/dev/Sandbox%E5%8E%9F%E7%90%86%E5%8F%8A%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97?id=sandbox%e5%8e%9f%e7%90%86%e5%8f%8a%e4%bd%bf%e7%94%a8%e6%8c%87%e5%8d%97)方案时使用CoreDNS+Etcd搭建了`vpc.ucloudadmin.com`的二级域名DNS系统，也在研究过Edns0的forward时偶尔翻过源码定位问题，因此此次源码阅读以CoreDNS作为对象研究实现。

## 源码阅读

CoreDNS的作用主要是实现DNS Server，因此其必须实现一个udp server，这方面CoreDNS主要借助了开源项目[caddy](https://github.com/caddyserver/caddy)来作为其server framework完成来开发，复用了其包括配置、框架、插件系统等模块，因此CoreDNS自身的逻辑是非常紧凑和简单的，因此后续系列二准备阅读下caddy的源码。

关于dns协议的实现，依赖了[miekg/dns: DNS library in Go](https://github.com/miekg/dns)这个库。

此外，CoreDNS实现了基于https、tls、grpc等多种协议的dns server。

### 处理信号

Caddy框架在启动时提供了`TrapSignals`函数来处理信号，可以看到这个函数的实现由`trapSignalsCrossPlatform`和`trapSignalsPosix`两部分组成：

```go
func TrapSignals() {
    trapSignalsCrossPlatform()
    trapSignalsPosix()
}
```

这是因为在golang os包中所有定义的信号中，只有`os.Interrupt` 和`os.Kill`保证在所有系统中都能生效(*The only signal values guaranteed to be present in the os package on all  systems are os.Interrupt (send the process an interrupt) and os.Kill (force  the process to exit)*)，其他信号则只支持符合POSIX要求的系统中。

### reuse port

在CoreDNS中实现`caddy.TCPServer`接口的`Listen() (net.Listener, error)`方法时，是这么实现的：

```go
import "github.com/coredns/coredns/plugin/pkg/reuseport"

// Listen implements caddy.TCPServer interface.
func (s *Server) Listen() (net.Listener, error) {
    l, err := reuseport.Listen("tcp", s.Addr[len(transport.DNS+"://"):])
    if err != nil {
        return nil, err
    }
    return l, nil
}
```

可以看到了其用到了`reuseport`这个模块，来看下实现。

在`reuseport`模块中，包含两个文件`listen_go111.go`和`listen_go_not111.go`两个文件，可以猜测前者是go1.11及其以上版本用到的源码文件，而后者则是go1.11以下版本编译时用到的源码文件，**那么编译中如何告诉编译器根据不同go版本引用不同源文件呢？**

看到源文件的顶行我们明白是用go的build tag来完成的：

listen_go111.go:

```go
// +build go1.11
// +build aix darwin dragonfly freebsd linux netbsd openbsd
```

listen_go_not111.go:

```go
// +build !go1.11 !aix,!darwin,!dragonfly,!freebsd,!linux,!netbsd,!openbsd
```

关于build tag可以参考下一小结，而reuesport在此处区分go版本主要是因为从go1.11才开始支持设置`SetSocketOption`（[Go 1.11 Release Notes](https://golang.org/doc/go1.11#net)），在此前的版本中并不支持。

`SO_REUSEPORT`是Linux内核从3.9开始支持的一项特性，主要是为了解决单线程listener，多线程accept时存在的性能和不均衡问题，使得多个进程可以监听在同一个tcp/udp port上，常见的应用场景包括`nginx`等。

传统方式：

![](media/coredns-1.png)

reuseport方式：

![](media/coredns-2.png)

此外，这个特性也被[KeyDB: A Multithreaded Fork of Redis](https://github.com/JohnSully/KeyDB)用来优化多线程版本的redis网络IO性能。

这里记录实现如下，后续可以复用：

```go
// +build go1.11
// +build aix darwin dragonfly freebsd linux netbsd openbsd

package reuseport

import (
    "context"
    "net"
    "syscall"
    "github.com/coredns/coredns/plugin/pkg/log"
    "golang.org/x/sys/unix"
)

func control(network, address string, c syscall.RawConn) error {
    c.Control(func(fd uintptr) {
        if err := unix.SetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_REUSEPORT, 1); err != nil {
            log.Warningf("Failed to set SO_REUSEPORT on socket: %s", err)
        }
    })
    return nil
}

// Listen announces on the local network address. See net.Listen for more information.
// If SO_REUSEPORT is available it will be set on the socket.
func Listen(network, addr string) (net.Listener, error) {
    lc := net.ListenConfig{Control: control}
    return lc.Listen(context.Background(), network, addr)
}

// ListenPacket announces on the local network address. See net.ListenPacket for more information.
// If SO_REUSEPORT is available it will be set on the socket.
func ListenPacket(network, addr string) (net.PacketConn, error) {
    lc := net.ListenConfig{Control: control}
    return lc.ListenPacket(context.Background(), network, addr)
}
```

#### Build tag

关于build tag:

> Build Constraints（Build Tag）：
> 
> In Go, a build tag, or a build constraint, is an identifier added to a piece of code that determines when the file should be included in a package during the build process. This allows you to build different versions of your Go application from the same source code and to toggle between them in a fast and organized manner. Many developers use build tags to improve the workflow of building cross-platform compatible applications, such as programs that require code changes to account for variances between different operating systems. Build tags are also used for integration testing, allowing you to quickly switch between the integrated code and the code with a mock service or stub, and for differing levels of feature sets within an application.

build tag提供了通过类似装饰器的方式来控制golang的编译过程，指定编译约束或编译条件，例如可以指定只在指定go版本或者os版本下编译某些文件或者忽略文件。

build tag的格式如下：

```go
// +build
```

`+build`必须出现在源文件的顶端（在包声明之前），同时和包的注释之间必须留有一行空行。同一行`+build`中的多个条件为OR关系，不同行的`+build`条件为AND关系。

示例：

```go
// 只在linux 386 或者 darwin的条件下编译
// +build linux,386 darwin

// 只在go1.11及以上版本中编译
// +build go1.11
```

build tag支持的指令主要来自于：

- the target operating system, as spelled by runtime.**GOOS**, set with the
  GOOS environment variable.
- the target architecture, as spelled by runtime.**GOARCH**, set with the
  GOARCH environment variable.
- the compiler being used, either "**gc**" or "**gccgo**"
- "**cgo**", if the cgo command is supported (see CGO_ENABLED in
  'go help environment').
- a term for each **Go major release**, through the current version:
  "go1.1" from Go version 1.1 onward, "go1.12" from Go 1.12, and so on.
- any additional tags given by the -tags flag (see 'go help build').

更多关于build tag的信息可以阅读[golang.org/cmd/go/#hdr-Build_constraints](https://golang.org/cmd/go/#hdr-Build_constraints).

### 插件模块

CoreDNS本身作为Caddy服务的一个插件存在，同时CoreDNS自身也支持非常多的插件用于处理DNS请求，这部分插件CoreDNS的实现比较精简。每个pluginHandler都实现了`Handler` 接口，而对于Plugin的定义则是输入一个Handler，输出为下一个待处理的handler这样一个function，最终通过函数栈完成pluginChain的处理。

```go
type (
    Handler interface {
        ServeDNS(context.Context, dns.ResponseWriter, *dns.Msg) (int, error)
        Name() string
    }
    Plugin func(Handler) Handler
)

func NewServer(addr string, group []*Config) (*Server, error) {
    // 省略上下文
    for _, site := range group {
        // compile custom plugin for everything
        var stack plugin.Handler
        for i := len(site.Plugin) - 1; i >= 0; i-- {
            stack = site.Plugin[i](stack)
        }
        site.pluginChain = stack
    }
}
```

### cache模块

在cache模块中，默认实现了sharding的功能，将cache分为256片，可以取得如下好处：

```go
import "hash/fnv"

// Cache is cache.
type Cache struct {
    shards [shardSize]*shard
}

// shard is a cache with random eviction.
type shard struct {
    items map[uint64]interface{}
    size  int

    sync.RWMutex
}

func key(qname string, m *dns.Msg, t response.Type) (bool, uint64) {
    // We don't store truncated responses.
    if m.Truncated {
        return false, 0
    }
    // Nor errors or Meta or Update.
    if t == response.OtherError || t == response.Meta || t == response.Update {
        return false, 0
    }

    return true, hash(qname, m.Question[0].Qtype)
}

func hash(qname string, qtype uint16) uint64 {
    h := fnv.New64()
    h.Write([]byte{byte(qtype >> 8)})
    h.Write([]byte{byte(qtype)})
    h.Write([]byte(qname))
    return h.Sum64()
}

// some cache method

// Add adds a new element to the cache. If the element already exists it is overwritten.
func (c *Cache) Add(key uint64, el interface{}) {
    shard := key & (shardSize - 1)
    c.shards[shard].Add(key, el)
}

// Get looks up element index under key.
func (c *Cache) Get(key uint64) (interface{}, bool) {
    shard := key & (shardSize - 1)
    return c.shards[shard].Get(key)
}

// Remove removes the element indexed with key.
func (c *Cache) Remove(key uint64) {
    shard := key & (shardSize - 1)
    c.shards[shard].Remove(key)
}
```

- 避免使用单一map并发情况下带来的锁竞争问题，分片完相当于将一把锁拆为256把；

- 将cache分为256片增加可扩展性，类似于redis的sharding，如果后续单个节点内存无法承受全部cache，则可以将部分sharding统一转给其他cache节点。

### single flight

`singleflight` 提供了重复函数执行抑制的功能，和`cache-service`中对相同并发sql进行去重的思路基本一致。

```go
// Package singleflight provides a duplicate function call suppression
// mechanism.
package singleflight

import "sync"

// call is an in-flight or completed Do call
type call struct {
    wg  sync.WaitGroup
    val interface{}
    err error
}

// Group represents a class of work and forms a namespace in which
// units of work can be executed with duplicate suppression.
type Group struct {
    mu sync.Mutex       // protects m
    m  map[uint64]*call // lazily initialized
}

// Do executes and returns the results of the given function, making
// sure that only one execution is in-flight for a given key at a
// time. If a duplicate comes in, the duplicate caller waits for the
// original to complete and receives the same results.
func (g *Group) Do(key uint64, fn func() (interface{}, error)) (interface{}, error) {
    g.mu.Lock()
    if g.m == nil {
        g.m = make(map[uint64]*call)
    }
    if c, ok := g.m[key]; ok {
        g.mu.Unlock()
        c.wg.Wait()
        return c.val, c.err
    }
    c := new(call)
    c.wg.Add(1)
    g.m[key] = c
    g.mu.Unlock()

    c.val, c.err = fn()
    c.wg.Done()

    g.mu.Lock()
    delete(g.m, key)
    g.mu.Unlock()

    return c.val, c.err
}
```

### little trick

```go
// Compile-time check to ensure Server implements the caddy.GracefulServer interface
var _ caddy.GracefulServer = &Server{}
```
