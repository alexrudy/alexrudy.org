---
layout: post
title: Tox-server, a mini RPC exercise
---

Twice now, I've found myself with tests designed to run in a containerized environment (via docker-compose both times). Containers make a great, quick way to get a bunch of software up and running, but they can be slow. Well, not slow in production, but they slow down the development cycle. If I have to run my tests via `docker run ...`, that gets tedious.

I've often seen it suggested that instead of `docker run ...`, I should do `docker exec` to run a command in a container. That's pretty handy, but the command line arguments can be a bit finicky. You have to remember the container you are pointed at, and its still slow (especially in the compose case, where docker compose can take a while to understand the state of your system). I found myself instead running `docker exec bash` in a container, leaving that shell running in some tab, and going back there.

That was great, but it really broke my finger memory to have one shell in `bash`, without my profile and my autocomplete setup. I could install [my environment](https://github.com/alexrudy/dotfiles) in the docker container, but that seems like a sledge-hammer solution to what is in the end a minor annoyance.

The right solution here is to do nothing, and live with one of the potential solutions above. I didn't do the right thing, because I like to play around with complicated tools. So instead, I made [tox-server][]. Its a tiny RPC (remote process call) server, with its own communication flavor, using [ZeroMQ]() sockets to call [tox][] repeatedly in a loop. 

## Using [tox-server][]

The usage is pretty simple. It requires 2 TCP ports (one for commands, one to stream output back to the client). On your remote host (where you want [tox][] to actually run):

```
$ tox-server -p9876 serve
[tox-server] Serving on tcp://127.0.0.1:9876
[tox-server] Output on tcp://127.0.0.1:9877
[tox-server] ^C to exit.
```

[tox-server][] does not choose consistent ports for you by default, you must give it at least the port you want to use for controlling the server. It will use one port higher for the streaming port, unless you specify that with the `-s` option. It also obeys the environment variables `TOX_SERVER_PORT` and `TOX_SERVER_STREAM_PORT` to change the two ports to known values. To communicate with the server, use the same `tox-server` command as a client:

```
$ tox-server run
GLOB sdist-make: ...
```

Any arguments to `tox-server run` are forwarded to `tox` on the remote host.

By default, [tox-server][] binds to `127.0.0.1` (localhost). To expose [tox-server][] (there is no authentication mechansim, so don't really expose it to the world), you should bind it to `0.0.0.0` with `tox-server run -b 0.0.0.0`.

[tox-server]: https://github.com/alexrudy/tox-server
[tox]: https://tox.readthedocs.io
[ZeroMQ]: https://zeromq.org

## Shutting it down

The server can be shut down with a quit command from the client, or killed via signal. The quit command is

```
tox-server quit
```

There is a healthcheck command, `ping`, which will just respond with the server's notion of the current time.


## Under the hood

What frankenstien moster have I wrought? It's pretty simple. The server listens on a [ZeroMQ][] `REP` socket, to reply to messages sent by the client. Clients are fair-queued against this `REP` socket by [ZeroMQ][] automatically. The `REP` socket expects a command, in the form of a python tuple, `("COMMAND", args)`, which is json'd and sent over the [ZeroMQ][] socket. 

Before sending the command, if it is a run command, the client creates a channel ID, and subscribes to it using a [ZeroMQ][] `SUB` channel. The server then runs the `tox` command in a subprocess and publishes output to the channel indicated by the client using a [ZeroMQ][] `PUB` socket. `STDOUT` and `STDERR` streams are respected (using different [ZeroMQ][] channels), and output buffering is minimized so you should see real-time updates from `tox` as if you were running it in your own terminal, even though behind the scenes, `tox` isn't running in a tty.

This works pretty well, the largest dissatisfactions I have is that there are no tests, and that it requires 2 TCP ports ([ZeroMQ][] is great for many things, but it doesn't multiplex things like this very well).