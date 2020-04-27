---
layout: post
title: Tox-server, a mini RPC exercise
---

Twice now, I've found myself with tests designed to run in a containerized environment (via docker-compose both times). Containers make a great, quick way to get a bunch of software up and running, but they can be slow. Well, not slow in production, but they slow down the development cycle. If I have to run my tests via `docker run ...`, that gets tedious.

<!--more-->

I've often seen it suggested that instead of `docker run ...`, I should do `docker exec` to run a command in a container. That's pretty handy, but the command line arguments can be a bit finicky. You have to remember the container you are pointed at, and its still slow (especially in the compose case, where docker compose can take a while to understand the state of your system). I found myself instead running `docker exec bash` in a container, leaving that shell running in some tab, and going back there.

That was great, but it really broke my finger memory to have one shell in `bash`, without my profile and my autocomplete setup. I could install [my environment](https://github.com/alexrudy/dotfiles) in the docker container, but that seems like a sledge-hammer solution to what is in the end a minor annoyance.

The right solution here is to do nothing, and live with one of the potential solutions above. I didn't do the right thing, because I like to play around with complicated tools. So instead, I made [tox-server][]. Its a tiny RPC (remote process call) server, with its own communication flavor, using [ZeroMQ]() sockets to call [tox][] repeatedly in a loop. 

## Using [tox-server][]

The usage is pretty simple. It requires a single open TCP port from the server. On your remote host (where you want [tox][] to actually run):

```
$ tox-server -p9876 -linfo serve
[serve] Running server at tcp://127.0.0.1:9876
[serve] ^C to exit
```

[tox-server][] does not choose a port for you by default, you must give it the port you want to use for controlling the server. It also obeys the environment variables `TOX_SERVER_PORT` to change the two ports to known values. To communicate with the server, use the same `tox-server` command as a client:

```
$ tox-server -p9876 run
GLOB sdist-make: ...
```

Any arguments to `tox-server run` are forwarded to `tox` on the remote host.

By default, [tox-server][] binds to `127.0.0.1` (localhost). To expose [tox-server][] (there is no authentication mechansim, so don't really expose it to the world), you should bind it to `0.0.0.0` with `tox-server run -b 0.0.0.0`.

You can make the client call a different host with the `-h` argument. But that often implies you've exposed [tox-server][] to the world, and thats a great way to have a huge security hole. Don't do that.

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

There is a healthcheck command, `ping`, which will just respond with the server's notion of the current time:

```
$ tox-server ping
{'time': 1587962661.826404, 'tasks': 1}
```

The response is JSON, and will tell you how many tasks are currenlty running, as well as the current time on the server. 

### Shutting it down

The server can be shut down with a quit command from the client, or killed via signal. The quit command is:

```
$ tox-server quit
DONE
```

# Building `tox-server`

What frankenstien moster have I wrought? It's pretty simple. It is essentially an implementation of RPC ("remote process call"), where the client sends a command, and the server listens in a loop and responds to those commands. I used [ZeroMQ][] to implement the network protocol part, largely because I'm familiar with ZeroMQ, and it makes some aspects (e.g. protocol design, socket identification) pretty easy.

The `run` command sends all of the arguments it recieves to the server, and the server calls `tox` with those arguments appended. Essentially no sanitization is done to the arguments, allowing for complex ways of calling `tox` to be passed through to the server. The commands are sent in a single [ZeroMQ message frame](http://zguide.zeromq.org/py:all#toc37), and encoded with JSON in a small object format. Responses are sent in the same format. Commands are identified by an enum, and responses generally are messages with the same enum.

I used `tox-server` as a chance to learn asynchronous programming in python, and to learn [asyncio][]. I want to use the rest of this post to discuss that experience, what made me learn [asyncio][], what went well, and what went poorly.

Since this gets quite long, here are a list of secitons:

- [Original Design](#original-synchronous-design): How I built [tox-server][] without [asyncio][].
- [Async Design](#asynchronous-design): How I built [tox-server][] with [asyncio][]
    - [Replacing Selectors](#replacing-selectors)
    - [Building the Server](#building-the-server)
    - [Building the Client](#building-the-client)
    - [Handling Interrupts](#handling-interrupts)
- [My Experience with asyncio](#the-asyncio-experience): Some thoughts on [asyncio][]
- [My Experience with `async/await`](#the-asyncawait-experience)

## Original Synchronous Design

Originally, I wrote a synchronous implementation of this program, using the [ZeroMQ poller](https://pyzmq.readthedocs.io/en/latest/api/zmq.html#polling) and the [`selectors` python module][selectors] to multiplex `tox`'s stdout and stderr. ZeroMQ and the selector module are not trivial to interact, and one of [ZeroMQ's strenghts](http://zguide.zeromq.org/py:all#Why-We-Needed-ZeroMQ) are its simple socket patterns, so I started with two paris of sockets. The server listens on a [ZeroMQ `REP`](https://zeromq.org/socket-api/#request-reply-pattern) socket, to reply to messages sent by the client. Clients are fair-queued against this `REP` socket by ZeroMQ automatically.

Before sending the command, if it is a run command, the client creates a channel ID, and subscribes to it using a [ZeroMQ `SUB` socket][ZMQ-PUB-SUB]. The server then runs the `tox` command in a subprocess and publishes output to the channel indicated by the client using a [ZeroMQ `PUB` socket][ZMQ-PUB-SUB]. `STDOUT` and `STDERR` streams are respected (using different [ZeroMQ topics][ZMQ-PUB-SUB]), and output buffering is minimized so that I can see real-time updates from `tox` as if I were running it in my own terminal, even though behind the scenes, `tox` isn't running in a tty.

There are a number of limitations to this synchronous design, which made me dissatisifed:

1. [ZeroMQ `REQ`-`REP`](https://zeromq.org/socket-api/#request-reply-pattern) pattern sockets require that each request is followed by one, and only one reply. This meant that I had to either buffer all of the output and send it in a single reply, send output in a separate socket, or use a different socket pattern. None of these are ideal solutions, so I worked up from buffered output, to a separate socket, to finally using a different socket pattern with [asyncio][].
2. When using multiple ZeroMQ sockets, as I was when I sent output over a [`PUB`-`SUB`][ZMQ-PUB-SUB] socket pair, requires having mulitple TCP ports open between the client and the server. This isn't so bad, but adds some complexity to the setup and operation of the server.
3. Streaming the output required that I use the [selectors module][selectors] to wait for read events from the `tox` subprocess, and ZeroMQ requires the use of its own [ZeroMQ poller][pyzmq-poller] which must be separate from the selector. It is possible to integrate [ZeroMQ poller][pyzmq-poller] with [selectors][], but it is quite complicated, and [pyzmq] has only implemented this integration in the context of asynchronous event loops.
4. Synchronous work made it difficult to interrupt running commands. A common pitfall I found was that I would start running some tests, realize I hadn't saved my changes, type `^C`, only to relaize that I had killed the client, but the server was still going to run all of the tox environments, producing a bunch of useless errors.

All of this meant that adding features or making small changes felt hazardous. It was easy to lose the thread of program flow, and I had to do a lot of manual management, especially at the intersection of the [ZeroMQ poller][pyzmq-poller] and [selectors][]. So I went head-first into an async re-write.

## Asynchronous Design

One choice in my async work was clear: I had to use [asyncio][]. [pyzmq supports](https://pyzmq.readthedocs.io/en/latest/eventloop.html#) [asyncio][], [gevent](https://www.gevent.org) and [tornado](https://github.com/facebook/tornado) for asynchronous IO. I didn't want to use tornado or gevent (nothing against either one, but I wanted the full glory of native `async`/`await` syntax), and that left me with [asyncio][]. [trio][] and [curio][] are very nice libraries, but they don't support [ZeroMQ][] yet (or, probably better put, [pyzmq][] doesn't yet support them). I really didn't want to implement my own eventloop integration on my first asynchronous project.

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
            # Encode data so that we can handle anything but still
            # send ASCII over the wire as JSON
            args = {
                "data": base64.b85encode(data).decode("ascii"), 
                "stream": key.data
            }
            socket.send_multipart([bchan, json.dumps(args).encode('utf-8')])

```
This version took the subprocess object (`Popen`), and then used a busy loop to send output. At each iteration of the loop, it uses the selector to wait for new data to be read, and if data is present, sends it out over the socket. The timeout is there so that we don't wait forever in `selector.select` when the process has ended and `proc.poll()` will return an exit code, ending the output loop.

The new async version looks like this:

```python
async def publish_output(
    reader: asyncio.StreamReader, 
    socket: zmq.asyncio.Socket, 
    message: Message, 
    stream: Stream, 
) -> None:

    while True:
        data = await reader.read(n=1024)
        if data:
            # Encode data so that we can handle anything but still
            # send ASCII over the wire as JSON
            args = {
                "data": base64.b85encode(data).decode("ascii"), 
                "stream": stream.name
            }

            message = message.respond(
                Command.OUTPUT, args=args
            )
            await message.send(socket)
```

Immediately, my selector code got much simpler. I didn't have to decide which sockets to wait on, and I didn't have to consider termination conditions. The `publish_output` coroutine runs as if its in a thread of execution all on its own, but with some pretty huge advantages:

1. It's not in a thread, so there isn't any overhead. Also, ZeroMQ sockets aren't thread safe, so I couldn't easily just create a thread in the synchronous world, I had to make sure everything happened in a hand-rolled eventloop.
2. It can be cancelled. Every `await` indicates a point where control can be interrupted. In the sync version, the output loop would only end when the process ended.
3. Because it can be cancelled, I no longer needed `proc.poll()` in the while loop, which means it can be cancelled at essentially any point. The synchronous version needed a short timeout so that it wouldn't get stuck at `selector.select()` when the process ends. The asynchronous coroutine needs no knowledge of the parent process. This also means that if I want to change the behavior of the parent process, I don't need to re-write the `selector.select()` code block.

In fact, with this new architecture, it's pretty easy to support process cancellation using [asyncio][]'s cancellation:
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

Overall, [asyncio][] made it pretty easy to replace selectors and drive the `tox` subprocess. Adding cancellation, and avoiding the busy selector loop with a short timeout went pretty well.

### Building the Server

Now that we can run `tox` commands, and send messages about the output they are producing, we need a loop to recieve commands and act on them. I built a whole `Server` object to handle the state of the server, but the core loop can be simplified like this:

```python
async def serve_forever(socket: zmq.asyncio.Socket) -> None:
    while True:
        message = await socket.recv_multipart()
        asyncio.create_task(handle_message(message, socket))
```

This turns our socket into a server which can respond to many commands at the same time – for each command recieved, it spins up a new coroutine, and lets the coroutine respond to the command when it is ready. The actual loop does a bit more work to keep track of active tasks, and allow them to be cancelled by a new command.

This setup wouldn't be possible in a synchronous context, even when using threads, because ZeroMQ sockets are not thread-safe. Its possible to use additional sets of ZeroMQ sockets for inter-thread communication, but this adds a lot of complexity and overhead. The [asyncio][] server's functionality can be implemetned in only a few lines of python, and natively handles the features I would have to implement elsewhere (concurrency, cancelling tasks).

One piece of synchronization is now required: locking the `tox` command, so that we don't run multiple copies of `tox` at the same time. This is pretty easy to do with `asyncio.Lock`.

### Building the Client

Sending commands to the server requires a client, and its pretty easy to build one without aysncio, but I chose to implement the client with asyncio (doing lots of asyncio was kind of the point of this project). A simplified version of the client looks like this:

```python
async def client(socket: zmq.asyncio.Socket, message: Message, timeout: Optional[float] = None) -> Message:
    await message.send(socket)

    while True:
        response = await asyncio.wait_for(Message.recv(client), timeout=timeout)
        if response.command == Command.OUTPUT:
            Stream[response.args["stream"]].fwrite(base64.b85decode(response.args["data"]))
        else:
            # Note: this assumes that OUTPUT is the only command which shouldn't end
            # the await loop above, which might not be true...
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

I set up an interrupt handler in [asyncio][] which watches for `SIGINT` (the signal sent by ^C). Instead of disrupting the eventloop, the first time this signal is recieved, it sends a message using the `socket` to the client requesting that the current task be cancelled.

## The Asyncio experience

I spent a weekend writing my first piece of serious code with [asyncio][]. What went well? What don't I like?

### The Good Parts

Python's `async/await` syntax was definitely helpful in getting this code running, and [asyncio][] provided a lot of the necessary batteries. The built in support for cancellation, creating new tasks, and introspecting task state is pretty nice.

Writing concurrent, but not threaded code freed me from having to think about a lot of potential syncrhonization primatives and state. For [tox-server][], speed isn't really the primary concern, so the lack of true parallel processing was less important than easy to reason-about code. I did use two synchronization primatives, a lock and an event, but both were easy to understand and get right. If this code were truly parallel, it would require a lot more synchronization, or a different archtecture to prevent ZeroMQ sockets from running on separate threads.

The code also became much more testable. It was much easier to isolate the subprocess work from the main process, and testing can proceed leveraging [asyncio][] primatives like `Future` to represent discrete changes in state. Because the code is concurrent, but not in parallel, it is trivial to pause the state of the server, assert something about that state, and then resume the server in a test.

### The bad parts

- Swallowing Errors
- Difficult to reason about whether another `await` is necessary for concurrent coroutines
- StreamReader.read is a pain, and returns too often.
- Backpressure is kind of difficult. 

Writing [asyncio][] ends up swallowing errors all over the place. The async code contains several places where I catch a `BaseException` only to log it, so that I can see some logger output

## The `async/await` Experience

- Concurrent code is much easier to write.
- I'm undecided about "function color", but maybe it is inverted?
- Some non-[asyncio][] libraries have nicer primatives (e.g. trio's nursery)

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