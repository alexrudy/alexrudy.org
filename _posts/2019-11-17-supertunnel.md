---
layout: post
title:  "SuperTunnel"
---

[SuperTunnel][st] is a tool I've often wanted for keeping SSH tunnels alive – mostly by just watching for when
a tunnel dies and starting a new one. Its a handy way to re-connect after some temporary loss of connection
like walking to a meeting, or going through a real tunnel on the train.

There are lots of other ways you can convince an SSH connection to stay open – and don't worry, you can use
those with [supertunnel][st] as well – it uses plain `ssh` under the hood.

I use [supertunnel][st] to open port forwarding to my jupyter notebooks when I'm working on a remote machine.

You can install [supertunnel][st] via pip:
```
pip install supertunnel
```

Then, use it like this:
```
st jupyter --auto jupyter.example.com
```


[st]:https://github.com/alexrudy/supertunnel