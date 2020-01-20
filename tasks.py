from invoke import task, Collection

import os
import json
import pprint
from pathlib import Path

ns = Collection()

def t(*args, **kwargs):
    """Custom task wrapper which also registers task in a namespace"""

    namespace = kwargs.pop("ns", ns)

    def _inner(f):
        _task = task(*args, **kwargs)(f)
        namespace.add_task(_task)
        return _task

    return _inner

def dc(c, command, **kwargs):
    c.run(f"docker-compose -f docker-compose.yml -f docker-compose.dev.yml {command}", **kwargs)

@t(aliases=("s", "server"))
def serve(c, detach=False):
    """Run the draft server."""
    c.config.run.pty = True
    detach = "-d" if detach else ""

    c.run(f"bundle exec jekyll serve {detach} --watch --drafts --host 0.0.0.0")

@t()
def up(c):
    """Stand up the production service"""
    dc(c, "up -d")

@t()
def down(c):
    """Bring down the service"""
    dc(c, "down")

@t()
def build(c):
    """Build the Jekyll container"""
    dc(c, "build")
    dc(c, "push")

@t()
def push(c):
    """Push the Jekyll container"""
    dc(c, "push")

@t(aliases=("bash",))
def shell(c):
    """Run a shell in the container."""
    c.config.run.pty = True
    dc(c, "exec nginx-alexrudy /bin/bash")

@t()
def logs(c):
    """Run a shell in the container."""
    c.config.run.pty = True
    dc(c, "logs")