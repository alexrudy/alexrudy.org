---
layout: post
title: 'Tox-server – an excuse to learn asyncio'
---

For a few projects I've found myself with tests designed to run in a containerized environment (often via docker-compose). Containers make a great, quick way to get a bunch of software up and running, but they can be slow. Well, not slow in production, but they sometimes slow down the local development cycle. If I have to run my tests via `docker run ...`, I get tired of waiting for the docker engine to start my containers.

<!--more-->

I like writing unit tests, and I want those tests to run quickly, and provide rapid feedback as to whether my change worked. The best test suites can test a subsection or change in a matter of a second or two, and tell me if I've introduced a bug (usually because I can't spell variable names consistently).

I've often seen it suggested that instead of `docker run ...`, I should do `docker exec` to run a command in a container. That's pretty handy, but the command line arguments can be a bit finicky. You have to remember the container you are pointed at (not just the image name), and its still slow (especially in the compose case, where docker compose can take a while to understand the state of your system). I found myself instead running `docker exec ... /bin/bash` in a container, leaving that shell running in some tab, and going back there every time I want to run my tests.

That was great, but it really broke my finger memory to have one shell in `bash`, without my profile and my autocomplete setup. I could install `zsh` and [my environment](https://github.com/alexrudy/dotfiles) in the docker container, but that seems like a sledge-hammer solution to what is in the end a minor annoyance.

The right solution here is to do nothing, and live with one of the potential solutions above. I didn't do the right thing, because I like to play around with complicated tools. So instead, I made [tox-server][]. Its a tiny RPC (remote process call) server, with its own communication flavor, using [ZeroMQ]() sockets to call [tox][] repeatedly in a loop. 

## Using [tox-server][]

The usage is pretty simple. It requires a single open TCP port from the server. On your remote host (where you want [tox][] to actually run):

```
$ tox-server -p9876 -linfo serve
[serve] Running server at tcp://127.0.0.1:9876
[serve] ^C to exit
```

[tox-server][] does not choose a port for you by default, you must give it the port you want to use for controlling the server. It also obeys the environment variable `TOX_SERVER_PORT` set and forget the port in your shell. To communicate with the server, use the same `tox-server` command as a client:

```
$ tox-server -p9876 run
GLOB sdist-make: ...
```

Any arguments to `tox-server run` are forwarded to `tox` on the remote host.

By default, [tox-server][] binds to `127.0.0.1` (localhost). To expose [tox-server][] (there is no authentication mechanism, so don't really expose it to the world, but in a local docker container, this might be okay), you should bind it to `0.0.0.0` with `tox-server run -b 0.0.0.0`.

You can make the client communicate with a different host with the `-h` argument. But that often implies you've exposed [tox-server][] to the world, and thats a great way to have a huge security hole. Don't do that.

### Interrupting your tests

If your tests hang (or, like me, you forgot to hit save), you can interrupt your tests with the standard `^C`
interrupt in your terminal. The first `^C` will request that the server cancel the running command. The second
`^C` will exit the local client.

You can try this with no server running, and sending the `quit` command::

```
$ tox-server -p9876 quit
^C
Cancelling quit with the server. ^C again to exit.
^C
Command quit interrupted!
```

### Checking on the server

There is a health check command, `ping`, which will get a message from the server:

```
$ tox-server ping
{'time': 1587962661.826404, 'tasks': 1}
```

The response is JSON, and will tell you how many tasks are currently running, as well as the current time on the server. 

### Shutting it down

The server can be shut down with a quit command from the client, or killed via signal. The quit command is:

```
$ tox-server quit
DONE
```

This gracefully shuts down the server after currently running tasks have finished.

# Writing tox-server

Why build something kind of complicated to solve an annoying task? Why not? It's pretty simple. It is essentially an implementation of RPC (remote process call), where the client sends a command, and the server listens in a loop and responds to those commands. I used [ZeroMQ][] to implement the network protocol part, largely because I'm familiar with ZeroMQ, and it makes some aspects (e.g. protocol design, socket identification, connections, and queuing) pretty easy.

The `run` command sends all of the arguments it receives to the server, and the server calls `tox` with those arguments appended. Essentially no sanitization is done to the arguments, allowing for complex ways of calling `tox` to be passed through to the server. The commands are sent in a single [ZeroMQ message frame](http://zguide.zeromq.org/py:all#toc37), and encoded with JSON in a small object format. Responses are sent in the same format. Commands are identified by an enum, and responses generally are messages with the same enum.

I used `tox-server` as a chance to learn asynchronous programming in python, and to learn [asyncio][]. I want to use the rest of this post to discuss that experience, what made me learn [asyncio][], what went well, and what went poorly.

Since this gets quite long, here are a list of sections:

- [Original Design](#original-synchronous-design): How I built [tox-server][] without [asyncio][].
- [Async Design](#asynchronous-design): How I built [tox-server][] with [asyncio][]
    - [Replacing Selectors](#replacing-selectors)
    - [Building the Server](#building-the-server)
    - [Building the Client](#building-the-client)
    - [Handling Interrupts](#handling-interrupts)
- [My Experience with asyncio](#the-asyncio-experience): Some thoughts on [asyncio][]
- [My Experience with `async`/`await`](#the-asyncawait-experience): Some thoughts on using `async`/`await` in python

Throughout the following sections, I'll share snippets of code from [tox-server][]. However, I've usually simplified the code to gloss over some of the additional work I did in [tox-server][] to factor out jobs like protocol design, error handling, and task bookkeeping. I'll try to link to the source for each example I provide if you want to see more of the details.

## Original Synchronous Design

Originally, I wrote a synchronous implementation of this program, using the [ZeroMQ poller](https://pyzmq.readthedocs.io/en/latest/api/zmq.html#polling) and the [`selectors` python module][selectors] to multiplex `tox`'s stdout and stderr. ZeroMQ and the selector module are not trivial to interact, and one of [ZeroMQ's strengths](http://zguide.zeromq.org/py:all#Why-We-Needed-ZeroMQ) are its simple socket patterns, so I started with two pairs of sockets. Controlling the server is done in a [request-reply pattern](https://zeromq.org/socket-api/#request-reply-pattern), where a client makes a request, and the server replies. [ZeroMQ][] implements this as a `REQ/REP` pair of sockets. The server listens on a `REP` socket, to reply to messages sent by the client. Clients use a `REQ` socket, and so are fair-queued against this `REP` socket by ZeroMQ automatically.

Output is handled in a [publish/subscribe pattern][ZMQ-PUB-SUB], where sockets are either publishers, which transmit data to many subscribers, or a subscriber, which read data from many publishers. Before sending the command, if it is a run command, the client creates a channel ID, and subscribes to it using a ZeroMQ `SUB` socket. The server then runs the `tox` command in a subprocess and publishes output to the channel indicated by the client using a ZeroMQ `PUB` socket. `STDOUT` and `STDERR` streams are respected (using different [ZeroMQ topics][ZMQ-PUB-SUB]), and output buffering is minimized so that I can see real-time updates from `tox` as if I were running it in my own terminal, even though behind the scenes, `tox` isn't running in a tty.

There are a number of limitations to this synchronous design, which made me dissatisfied:

1. [ZeroMQ `REQ`-`REP`](https://zeromq.org/socket-api/#request-reply-pattern) pattern sockets require that each request is followed by one, and only one reply. This meant that I had to either buffer all of the output and send it in a single reply, send output in a separate socket, or use a different socket pattern. None of these are ideal solutions, so I worked up from buffered output, to a separate socket, to finally using a different socket pattern only after I switched to [asyncio][].
2. When using multiple ZeroMQ sockets, as I was when I sent output over a [`PUB`-`SUB`][ZMQ-PUB-SUB] socket pair, requires having multiple TCP ports open between the client and the server. This isn't so bad, but adds some complexity to the setup and operation of the server.
3. Streaming the output required that I use the [selectors module][selectors] to wait for read events from the `tox` subprocess, and ZeroMQ requires the use of its own [ZeroMQ poller][pyzmq-poller] which must be separate from the selector. It is possible to integrate [ZeroMQ poller][pyzmq-poller] with [selectors][], but it is quite complicated, and [pyzmq] has only implemented this integration in the context of asynchronous event loops.
4. Synchronous work made it difficult to interrupt running commands. A common pitfall I found was that I would start running some tests, realize I hadn't saved my changes, type `^C`, only to realize that I had killed the client, but the server was still going to run all of the tox environments, producing a bunch of useless errors.

All of this meant that adding features or making small changes felt hazardous. It was easy to lose the thread of program flow, and I had to do a lot of manual management, especially at the intersection of the [ZeroMQ poller][pyzmq-poller] and [selectors][]. So I went head-first into an async re-write.

## Asynchronous Design

One choice in my async work was clear: I had to use [asyncio][]. [pyzmq supports](https://pyzmq.readthedocs.io/en/latest/event loop.html#) [asyncio][], [gevent](https://www.gevent.org) and [tornado](https://github.com/facebook/tornado) for asynchronous IO. I didn't want to use tornado or gevent (nothing against either one, but I wanted the full glory of native `async`/`await` syntax), and that left me with [asyncio][]. [trio][] and [curio][] are very nice libraries, but they don't support [ZeroMQ][] yet (or, probably better put, [pyzmq][] doesn't yet support them)[^1]. I really didn't want to implement my own event loop integration on my first asynchronous project.

With that out of the way, the rest of the design started by reproducing the synchronous version, and slowly adding in various asynchronous concepts.

### Replacing Selectors

Here is where I had the first asynchronous victory – I replaced and removed all of the [selectors][] code, adding a single coroutine for output of either `stdout` or `stderr` from `tox`.

The original selectors code looked somewhat like this:
```python
def publish_output(proc: subprocess.Popen, channel: str, socket: zmq.asyncio.Socket) -> None:
    bchan = channel.encode("utf-8")

    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, events=selectors.EVENT_READ, data="STDOUT")
    selector.register(proc.stderr, events=selectors.EVENT_READ, data="STDERR")

    while proc.poll() is None:
        for (key, events) in selector.select(timeout=0.01):
            data = key.fileobj.read(1024)
            socket.send_multipart([bchan, data])

```
This version took the subprocess object (`Popen`), and then used a busy loop to send output. At each iteration of the loop, it uses the selector to wait for new data to be read, and if data is present, sends it out over the socket. The timeout is there so that we don't wait forever in `selector.select` when the process has ended and `proc.poll()` will return an exit code, ending the output loop.

The [new async version](https://github.com/alexrudy/tox-server/blob/master/tox_server/process.py#L110) looks like this:

```python
async def publish_output(
    reader: asyncio.StreamReader, 
    socket: zmq.asyncio.Socket, 
    stream: Stream, 
) -> None:

    while True:
        data = await reader.read(n=1024)
        if data:
            await socket.send_multipart([stream.name, data])
```

Immediately, my selector code got much more straightforward. I didn't have to decide which sockets to wait on, and I didn't have to consider termination conditions. The `publish_output` coroutine runs as if its in a thread of execution all on its own, but with some pretty huge advantages:

1. It's not in a thread, so there isn't any overhead. Also, ZeroMQ sockets aren't thread safe, so I couldn't easily just create a thread in the synchronous world, I had to make sure everything happened in a hand-rolled event loop.
2. It can be cancelled. Every `await` indicates a point where control can be interrupted. In the sync version, the output loop would only end when the process ended.
3. Because it can be cancelled, I no longer needed `proc.poll()` in the while loop, which means it can be cancelled at essentially any point. The synchronous version needed a short timeout so that it wouldn't get stuck at `selector.select()` when the process ends. The asynchronous coroutine needs no knowledge of the parent process. This also means that if I want to change the behavior of the parent process, I don't need to re-write the `selector.select()` code block.

You might say that the code itself doesn't look that different, and you would be correct, but the synchronous version has more going on – more complexity to be aware of, more interacting pieces of the overall application. `async def publish_output` has only a single concern, sending output over the socket, and all of the rest of the application is left elsewhere, meaning that adding features or changing something about the way the server works doesn't need to impact `async def publish_output`.

In fact, with this new architecture, it's pretty easy to support process cancellation using [asyncio][]'s cancellation – [the version in tox-server](https://github.com/alexrudy/tox-server/blob/master/tox_server/process.py#L44) looks kind of like this:
```python
async def run_command(args: str, socket: zmq.asyncio.Socket, template: Message) -> subprocess.CompletedProcess:
    proc = await asyncio.subprocess.create_subprocess_shell(
        args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )

    output_tasks = {
        asyncio.create_task(publish_output(proc.stdout, output, template, Stream.STDOUT)),
        asyncio.create_task(publish_output(proc.stderr, output, template, Stream.STDERR)),
    }

    try:
        returncode = await proc.wait()
    except asyncio.CancelledError:
        proc.terminate()
        returncode = await proc.wait()
    finally:
        for task in output_tasks:
            task.cancel()
        await asyncio.wait(output_tasks)
    return subprocess.CompletedProcess(args, returncode=returncode)
```

This demonstrates a few things:

1. `asyncio.create_task` will set a coroutine in motion which will happen in "parallel" with the current coroutine (of course, since asyncio uses a single thread, its not really in parallel)
2. Cancellation is a regular python exception, and I can catch it to ensure that the subprocess cleans up properly. The `try ... finally` block is also useful for cleaning up parallel coroutines.

Notice, that the implementation of cancellation can be done without really understanding the details of `publish_output`. To implement cancellation in the synchronous version, we would have had to teach the synchronous `publish_output` about cancellation, and probably change so that our selector listens to something which could indicate when a cancellation might have occurred, interrupting the loop. And thats just one feature!

Overall, [asyncio][] made it pretty easy to replace selectors and drive the `tox` subprocess. Adding cancellation, and avoiding the busy selector loop with a short timeout went pretty well, and I was off to a good start.

### Building the Server

Now that we can run `tox` commands, and send messages about the output they are producing, we need a loop to receive commands and act on them. I built a whole `Server` object to handle the state of the server, but the [core loop](https://github.com/alexrudy/tox-server/blob/master/tox_server/server.py#L107) can be simplified like this:

```python
async def serve_forever(socket: zmq.asyncio.Socket) -> None:
    while True:
        message = await socket.recv_multipart()
        asyncio.create_task(handle_message(message, socket))
```

This turns our socket into a server which can respond to many commands at the same time – for each command received, it spins up a new coroutine, and lets the coroutine respond to the command when it is ready. The actual loop does a bit more work to keep track of active tasks, and allow them to be cancelled by a different command.

The function `async def handle_message` does only a little more than `run_command` above, in that it handles the other types of messages a client might send along.

This setup wouldn't be possible in a synchronous context, even when using threads, because ZeroMQ sockets are not thread-safe. Its possible to use additional sets of ZeroMQ sockets for inter-thread communication, but this adds a lot of complexity and overhead. The [asyncio][] server's functionality can be implemented in only a few lines of python, and natively handles the features I would have to implement elsewhere (concurrency, cancelling tasks).

One piece of synchronization is now required: locking the `tox` command, so that we don't run multiple copies of `tox` at the same time. This is [pretty easy to achieve](https://github.com/alexrudy/tox-server/blob/master/tox_server/server.py#L220) with `asyncio.Lock`.

### Building the Client

Sending commands to the server requires a client, and its pretty easy to build one without asyncio, but I chose to implement the client with asyncio (doing lots of asyncio was kind of the point of this project). A simplified [version of the client](https://github.com/alexrudy/tox-server/blob/master/tox_server/client.py#L53) looks like this:

```python
async def client(socket: zmq.asyncio.Socket, message: Message, timeout: Optional[float] = None) -> Message:
    await message.send(socket)

    while True:
        response = await asyncio.wait_for(Message.recv(client), timeout=timeout)
        if response.command == Command.OUTPUT:
            Stream[response.args["stream"]].write(response.data)
            Stream[response.args["stream"]].flush()
        else:
            # Non-OUTPUT commands indicate we are done processing the commadn and should end.
            break
    return response
```

This client can handle multiple responses for the same command, which removes one of the rough spots in the original, synchronous design – with this client, I can send both commands and outputs over the same socket, with no worries about whether that socket must be shared between threads or interrupted. I did have to change the socket pattern to a fully asynchronous pattern, [`DEALER-ROUTER`](https://zeromq.org/socket-api/#request-reply-pattern).

### Handling interrupts

The last feature I built for [tox-server][] is interrupt handling. Interrupt handling is easy to demonstrate by running a command from a client when no server is running:
```
$ tox-server -p9876 quit
^C
Cancelling quit with the server. ^C again to exit.
^C
Command quit interrupted!
``` 

I set up an [interrupt handler in tox-server](https://github.com/alexrudy/tox-server/blob/master/tox_server/interrupt.py#L17) which watches for `SIGINT` (the signal sent by ^C). Instead of disrupting the event loop, the first time this signal is received, it sends a message using the `socket` to the client requesting that the current task be cancelled.

## The Asyncio experience

I spent a weekend writing my first piece of serious code with [asyncio][]. What went well? What don't I like?

### The Good Parts

Python's `async`/`await` syntax was definitely helpful in getting this code running, and [asyncio][] provided a lot of the necessary batteries. The built in support for cancellation, creating new tasks, and introspecting task state is pretty nice.

Writing concurrent, but not threaded code freed me from having to think about a lot of potential synchronization primitives and state. For [tox-server][], speed isn't really the primary concern, so the lack of true parallel processing was less important than easy to reason-about code. I did use two synchronization primitives, a lock and an event, but both were easy to understand and get right. If this code were truly parallel, it would require a lot more synchronization, or a different architecture to prevent ZeroMQ sockets from running on separate threads[^2].

The code also became much more testable. It was much easier to isolate the subprocess work from the main process, and testing can proceed leveraging [asyncio][] primitives like `Future` to represent discrete changes in state. Because the code is concurrent, but not in parallel, it is trivial to pause the state of the server, assert something about that state, and then resume the server in a test.

I found writing async tests to be even better for inherently concurrent code. One simple quality of life improvement: timeouts. Often, when writing concurrent code, failure is a deadlock. This means having to manually interrupt running code, hope for a traceback, and debug from there. Instead, I wrote a quick wrapper for my async tests to add a timeout:

```python
F = TypeVar("F", bound=Callable)

def asyncio_timeout(timeout: int) -> Callable:
    def _inner(f: F) -> F:
        @functools.wraps(f)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            return await asyncio.wait_for(f(*args, **kwargs), timeout=timeout)

        return wrapper

    return _inner
```

This kind of timeout is difficult to correctly implement in pytest without asyncio, and behaves really poorly when interacting with [ZeroMQ][] in synchronous mode, but in asynchronous mode, it is a dream.[^4]

### The bad parts

Writing [asyncio][] ends up swallowing errors all over the place. The async code contains several places where I catch a `BaseException` only to log it, so that I can see some logger output. In other places, I can turn on asyncio debugging, and then watch for errors on stderr. This is less than ideal - I'd much rather have even these debugging messages raise real errors in my application, so that I can test that my loops don't leave dangling coroutines, or fail to await coroutines.[^5]

I also find it difficult to reason about whether I need to provide an additional `await` for coroutines which I expect to cancel. In some places, I have found it helpful to add an `await` after canceling a task, to allow that task to finish, but I'm never really sure if that is necessary or correct. I found myself wishing for trio and curio's nursery concept, which provides a context within which all coroutines scheduled must finish.

#### A StreamReader bug

I found a big pain point in [StreamReader](https://docs.python.org/3/library/asyncio-stream.html#asyncio.StreamReader)'s `.read()` method. For `tox-server`, I want to read from a subprocess's `stdout` and `stderr`. Ideally, I'd like to read as often as possible, as many testing applications (like `pytest`, or `tox` in parallel mode) use ANSI escape codes and control sequences to animate output lines. Just sending each line of output isn't really good enough. Naively, I used `await stream.read(n=1024)`, basically asking the event loop for _up to 1024_ bytes from the stream. Unfortunately, I found that only `await`-ing the stream resulted in a busy loop, where the output reader task would take-over and no other task would get a chance to run. To solve this, I had to check the stream for the EOF return `b""` on each loop iteration. Otherwise, in the EOF state, the stream would hog all of the processing power in the event loop, and never give other tasks a chance to run. In the end, what I find surprising is not the use of `b""` as the sentinel for EOF, but rather that the loop ends up busy in the EOF state, and no other task gets an opportunity to run.

## The `async`/`await` Experience

Nathan Smith wrote a good [blog post on the pitfalls and difficulties of asyncio](https://vorpus.org/blog/some-thoughts-on-asynchronous-api-design-in-a-post-asyncawait-world/) which I highly recommend. Some of the pain points I felt above are probably related to the use of [asyncio][], and certainly having a feature like nurseries would have been helpful.

However, this wasn't just an exercise in learning [asyncio][] for me – this was the first significant program I've every written using `async`/`await` in python. In the future, if I have an opportunity to write another asynchronous program, and I'm not bound to [asyncio][], I would definitely try one of the other libraries.

### Colorful functions

Finally, there is still something a little bit painful about having to add `await` in a lot of places. There is an allegory used for async programming: ["What color is your function?"](http://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/) which demonstrates this problem in more detail, but to get down to it, why do we need to annotate our function calls with `await` anyhow? Some languages implicitly insert `await` where necessary (in particular, Go does a good job of doing this). The argument against inserting `await` implicitly is that it lets the programmer know where their program might be suspended.

I'd argue that `await` isn't actually very useful as such. It does tell you where your program _might_ return control to the event loop, but as in [the bug I squashed above](#a-streamreader-bug), `await` doesn't guarantee that the program will get interrupted. In fact, there is nothing to stop the following pathological function:
```python
async def evil():
    while True:
        pass
```

This busy-loop will run forever, and no amount of `asyncio.wait_for` with a timeout or `task.cancel()` will be able to interrupt it. What good am I doing as a programmer when I have to write `await evil()`?

One might argue that `await` is necessary due to how `async`/`await` is implemented, but that doesn't seem like a good excuse. I'll admit I haven't explored what python might look like without colorful functions, but I'd be interested to think more about how to make `async`/`await` a little less naive than the `evil()` example above.[^3]

# Wrapping Up

For concurrent programming, and network I/O in general, I really like the `async`/`await` paradigm, and I'm excited to use it elsewhere (Rust? 😏). Its clear to me that there is still some work to be done, both in the libraries, but also in how we think about `async`/`await` syntax. I'm looking forward to another dive into the `async` python world.

[tox-server]: https://github.com/alexrudy/tox-server
[tox]: https://tox.readthedocs.io
[ZeroMQ]: https://zeromq.org
[ZMQ-PUB-SUB]: https://zeromq.org/socket-api/#publish-subscribe-pattern
[pyzmq-poller]: https://pyzmq.readthedocs.io/en/latest/api/zmq.html#polling
[pyzmq]: https://pyzmq.readthedocs.io/en/latest/
[asyncio]: https://docs.python.org/3/library/asyncio.html
[selectors]: https://docs.python.org/3/library/selectors.html
[trio]: https://trio.readthedocs.io/en/stable/
[curio]: https://curio.readthedocs.io/en/latest/

---

[^1]: Honestly, ZMQ might not be the right tool for the job here, and I did consider switching to a plain old TCP socket, but ZMQ does provide a nice wire protocol (automatically length delimited), resilient connections, and the ability to trivially switch between transports by providing a different connection URI to ZMQ.
[^2]: This kind of freedom and easy reasoning was so surprising, I found myself sometimes writing more complicated code, and then simplifying it when I realized I didn't need to account for some piece of shared state, since it isn't really "shared" in a single asyncio event loop.
[^3]: This is actually another design principle for [trio][], which tries to implement structured concurrency such that every async function must yield control at least once, but there is nothing about the language which enforces this notion, leaving a rather large foot-gun for programmers who aren't as careful as [trio][] core contributors.
[^4]: I really wish I could cancel running tasks instead of just timing out – so that the tracebacks in pytest would point to the running task, not the timeout. This would be a good potential improvement to my timeout test decorator.
[^5]: This is a design principle for [trio][], and a reason I'd really like to try using trio for structured concurrency.