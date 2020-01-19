---
layout: post
title: "A python environment"
---

Setting up a good python environment for development can be pretty thorny -- largely because using your system python and installing packages globally with `pip`, is often a bad idea. On macos, the system python is usually a pretty old version:
```
$ /usr/bin/python --version
Python 2.7.16
```
and installing packages globally (using the system python) can result in conflicting requirements, difficult upgrades, and poor isolation if you want to share your work or move from one environment to another.

<!--more-->

There are a hunderd and one different ways to set up a python environment -- this is mine. It may not be the best, but there are a number of aspects I really like about it.

# The Setup

Here I'll walk through **how** I set up my python installation(s). Under [principles](#principles) I'll describe the "why" behind a bunch of these choices, and what I do to work within that framework.

The stack I leverage is roughly:

- [pyenv][] to manage python versions.
- [pyenv-virtualenv][] to manage virtual environments.
- [pip][] or [pipenv][] to manage dependencies.
- [pipx][] for command line tools *which happen to be written in python*.

If you are of the TLDR type, my high-level recommendation is: 

*Everything goes in a virtual environment, managed by [pyenv][] and activated locally. Use [pip][], [pipenv][], or [poetry][] to install your requirements, depending on your taste and how well locked down you want your dependencies to be. Use [pipx][] to install any end-user tools which don't really depend on a working python project.*

## Getting Started

My environment assumes that you have a package manager installed. On macos, I use [homebrew (`brew`)][homebrew] to install things, but I've worked with this environment with Ubuntu (where I'd default to using `apt-get` and friends).

You'll also need an environment where you can set and adjust the default variables in your shell. Editing a `.bashrc` file (or whatever flavor is appropriate for your shell profile) with a good text editor is a must. If you are comfortable with git, and a little bit of shell programming, I recommend you version your dotfiles (google it!). My [dotfiles][] are on github, and kept up to date. I'll reference various tools from my dotfiles here as we set up a python environemnt.

## [pyenv][] Python Version Management

[pyenv][] is the primary tool in my python arsenal. It manages multiple installations and versions of python pretty well,
and has a decently smart way of selecting between them.


### Installing [pyenv][]

Get [pyenv installed](https://github.com/pyenv/pyenv#installation) using their directions. If you are on macos, that might be as simple as `brew install pyenv`, but it might be more complicated. RTFM.

Be sure to add `pyenv init` to your shell initialization files. I have something akin to the following snippet in my dotfiles (see [`dotfiles/python/pyenv.sh`](https://github.com/alexrudy/dotfiles/blob/master/python/pyenv.sh) for the one which uses my shell functions):
```zsh
# somewhere in your .bash_profile or .zshrc

if [[ -d "$HOME/.pyenv" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
fi

# Don't set up pyenv if it doesn't exist.
# so we gracefully degrade when pyenv isn't installed.
if command -v pyenv 1>/dev/null 2>&1; then
    eval "$(pyenv init -)"
fi
```

At this point, you should be able to run `pyenv --help`, and `pyenv versions`, which should show you that you only have the system-provided python installed:

```
$ pyenv versions
* system
```

### Python build dependencies

To use pyenv to install python versions, you might require build dependencies (the tools used to compile a local version of python -- pyenv builds and compiles python from source once for each version). On macos, you'll need the apple developer command line tools. You can install these with `xcode-select -install`. You will also need readline and xz (`brew install readline xz` on macos, see [the pyenv wiki](https://github.com/pyenv/pyenv/wiki/Common-build-problems#prerequisites) for more details on other platforms). 

Once you've done this, you may be able to run `pyenv install 3.7.5` to install python version 3.7.5 using pyenv. On recent versions of macos, this will probably fail (see [this page on the pyenv wiki](https://github.com/pyenv/pyenv/wiki/Common-build-problems) for more information, or read on!). To get around this, I've developed a tiny helper script for installing python versions on macos, whhich sets the proper environment variables. You can get that script at [`dotfiles/pyenv/bin/pyenv-macbuild`](https://github.com/alexrudy/dotfiles/blob/master/python/bin/pyenv-macbuild), and placing it somewhere on your `PATH` will allow you to run `pyenv macbuild` which will invoke `pyenv install`, but with environment variables set properly for macos. The script is pretty simple:
```zsh
#!/usr/bin/env sh
#
# Summary: Helpers to build python on macos 10.14+
#
# Usage: pyenv macbuild <arguments>
#
# Set environment and build python on macos 10.14+, passing
# all arguments directly to pyenv install.

set -e
[ -n "$PYENV_DEBUG" ] && set -x

# Provide pyenv completions
if [ "$1" = "--complete" ]; then
  pyenv-install $@
  exit
fi

export SDKROOT="$(xcode-select -p)/SDKs/MacOSX.sdk"
export MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion | awk -F. '{print($1"."$2)}')
export CFLAGS="-I$(brew --prefix openssl)/include -I$(brew --prefix readline)/include -I${SDKROOT}/usr/include" 
export CPPFLAGS="-I$(brew --prefix zlib)/include" 
export LDFLAGS="-L$(brew --prefix openssl)/lib -L$(brew --prefix readline)/lib"

pyenv-install $@
```

Although you could set all of these environment variables once in your shell, I've found that causes as many problems as it solves. Build settings should be specific to what you are building (python with pyenv in this case) and not global across everything you do on your computer. Using a wrapper script like this ensures that the environment variables will only be around as long as the command `python macbuild` is running.

### Always getting the latest python version

I also recommend installing [xxenv-latest][], a tool for getting the latest version installed (so you don't have to remember what the most recent version of python is). With `pyenv-latest` set up, you can run this command on macos to install the latest version:
```zsh
pyenv macbuild $(pyenv latest --print)
```
On other systems (not macos), you can run
```
pyenv latest install
```
 to achieve the same effect. Unfortunately, the `pyenv-macbuild` shim above doesn't integrate with `pyenv latest` right now.[^1]

### Using pyenv to select python interpreters

Now you can install multiple versions of python on your system, and [pyenv][] will do a decent job keeping them separate. However, if you have no version of python selected, [pyenv][] will conservatively assume nothing, and not let you run any python commands. I recommend you set a global python version. Really, I recommend two global python versions, so that you always have a copy of `python` at your fingertips, and so that `python2` on your command line still points to an old copy of python2[^2]. To do this, I use the `pyenv global` command, which I have set to the following:

```zsh
pyenv global 3.7.5 2.7.16
```

This means that globally, **unless you override this setting**, binaries normally made available by python 3 or python 2, will default to using python 3.7.5 first and 2.7.16 if they can't be found. So the `python` command, and the `python3` command will both point to 3.7.5, and the `python2` command will point to 2.7.16. The same logic applies to the `pip`, `pip3`, and `pip2` commands.

A really awesome feature of pyenv is that you can locally override python versions on a per-directory basis, using the `pyenv local` command, which just adds your python version to a file `.python-version` in the current directory[^3].

For even more local work, you can use `pyenv shell` to override the python version in only the **current shell** and its decendents.

## Virtual Environments

[pyenv][] provides a way to install different python *versions*, but it doesn't isolate python environments (ignore the "env" in the name). As such, if we start or work on two separate projects, both of which we develop against python 3.7.5, we'll need some way to keep the requirements of those projects separate. This is good both because different projects might have requirements which conflict, and because its good to isolate your project and ensure that you are testing it against *only* the required dependencies, not silently introducting other dependencies into your workspace.

The traditional ways of managing virtual environments are *fine*, but they don't integrate with `pyenv`, and so don't respect the handy `.python-version` file used to set local python versions. I think this integration is pretty critical to a seamless python workflow. I really dislike having to remember to *activate* and *deactivate* a python environment when I start or stop working on a project. I'd rather just have that environment *just work* when I'm in a project directory, developing.

Enter [pyenv-virtualenv]. It lets you set up virtual environments which behave like full pyenv versions, and can be selected with commands like `pyenv global` and `pyenv local`. Install it following the [installation instructions](https://github.com/pyenv/pyenv-virtualenv#installation) or using homebrew if you are on macos (`brew install pyenv-virtualenv`). Be sure to follow the step about adding `eval $(pyenv virtualenv-init)` to your shell initialization functions. If you've done that using the snipped in the section above, you can modify it as follows:
```zsh
# somewhere in your .bash_profile or .zshrc

if [[ -d "$HOME/.pyenv" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
fi

# Don't set up pyenv if it doesn't exist.
# so we gracefully degrade when pyenv isn't installed.
if command -v pyenv 1>/dev/null 2>&1; then
    eval "$(pyenv init -)"
    
    # Set up pyenv-virtualenv only if pyenv is also set up.
    if command -v pyenv-virtualenv 1>/dev/null 2>&1; then
        eval "$(pyenv virtualenv-init -)"
    fi
fi
```

Now we have a set up where we can create a new virtualenv (named `my-virtualenv`) with the command `pyenv virtualenv 3.7.5 my-virtualenv`, and have `my-virtualenv` as a version we can use with `pyenv local` and friends.

This makes for a pretty straight-forward workflow when starting work on a new (or existing project):

1. Go to the directory where you'll work on your project.
2. Create a virtual environment with `pyenv virtualenv <version> <name>`.
3. Set `<name>` as the default python version for the project with `pyenv local <name>`.

Now, whenever you are in the project directory, `pyenv` will select the appropraite python version and virtual environment.

This setup should play well with other tools which rely on virtual environments (e.g. my ZSH prompt which shows the virtual environment "just works", and [pipenv][] properly recognizes the virtual environment you already have set up).

If you've been following along and adding custom `pyenv` commands like `pyenv macbuild` above, you can add a pyenv command which automates the process of creating a virtual environment. Mine is called [`pyenv project`]() and looks like this:
```zsh
#!/usr/bin/env sh
#
# Summary: Create a new virtual environment, and set it as the local python version
#
# Usage: pyenv project <version> <virtualenvname>
#
# Uses a pyenv python to create a virtual environment and set the local python version
# in the project directory to use the new virtual environment. Run this once, and in
# the future, when you are in the project directory, pyenv will default to using your
# virutal environment.


set -e
[ -n "$PYENV_DEBUG" ] && set -x

# Provide pyenv completions
if [ "$1" = "--complete" ]; then
  pyenv-virtualenv $@
  exit
fi

PROJECT_NAME=$(basename $(pwd))
PYENV_TARGET_VERSION=$1
VIRTUALENV_NAME=${2:-$PROJECT_NAME}

pyenv-virtualenv $PYENV_TARGET_VERSION $VIRTUALENV_NAME
pyenv-local $VIRTUALENV_NAME
```

Now you should have a working python environment. If it isn't working, continuing won't really help. When you find problems, feel free to submit a pull request or issue against [this blog post](https://github.com/alexrudy/alexrudy.net).

## Installing Python Dependencies

There are a few good options (and many strongly held opinions) about how to install python dependencies. I have some weakly held opinions, since I think almost no option is great.

### Just use pip

For quick projects or interactive work that I don't care about deploying or making repeatable, I'll rely on `pip install` to grab the dependencies that I need. When it turns out that I do need to share the quick and interactive projects I've been working on, running `pip freeze > requirements.txt` is usually good enough to have a saved environment I can pass along to a colleague or friend.

### Use Pipenv for applications

For applications, or other projects which I might deploy some day, I tend to reach for [pipenv][], which is a tool that is quite opinionated, but pretty good at installing precisely the versions of packages that you want. There are several downsides to [pipenv][] (its so opinionated it can be inflexible, there are a couple of corner case bugs that complex projects might run into while upgrading dependencies, its hard to debug, and its slow to install and slow to lock dependencies, to name a few), but it works pretty well, and feels like a much better solution than maintaining a pile of `requirements.txt` files with pinned versions. 

I find [pipenv][] works really well for applications with a lot of dependencies which probably won't change very often, but where you want the flexibility of fixing some versions, and letting other dependency versions float. [pipenv][] lets you express your applications requirements (installing depenncies using `pipenv install`) and then control upgrades (by running `pipenv upgrade`) to ensure that there is a consistent source of truth for your dependencies. You can then commit your machine-readable `Pipfile.lock` along side your `Pipfile`, to ensure that your requirements don't change on your end users.

## Install end-user applications with [pipx][]

Sometimes you want to install a python tool which isn't really a member or dependency in a single project, or which you want to run from everywhere. My go-to example for this category is [tmuxp][], a way to save and reload tmux sessions which deserves a blog post of its own. I want to use [tmuxp][] from anywhere, and I don't really care for it to be tracked as a dependency of any particular project. It has been stable for a while, and the tool version isn't as important to me as my ability to start and stop tmux sessions at will. I therefore install [tmuxp][] using [pipx][].

On macos, you can install pipx with
```zsh
brew install pipx
pipx ensurepath
```
or you can install `pipx` using `pip`. If you go the non-homebrew way, I recommend installing `pipx` with your favorite python version. This is mostly fine, but if you installed `pipx` in your global python 3.7.5 installation (a fine choice in this case), it won't be accessible when you are in a project which sets a different python version (or virtual environment) using `.python_version`. `pipx` is the only command where this isn't the desired behavior (`pipx` should be globally availalbe and not dependent on your python projects, most other python commands should follow a particular project around).

You should also ensure that the `pipx` path components are **before** the pyenv ones, so that programs installed with `pipx` take precedence over `pyenv` versions. This means that `.local/bin` should be before `.pyenv/shims` in your path.

Now you can install python end user programs like `tmuxp` using `pipx` in much the same way you would have used `pip`:
```zsh
pipx install tmuxp
```

[pipx][] will create an isolated virtual environment just for [tmuxp][] in this case, install it there, and make the [tmuxp][] binary accessible on your path.

I try to install any end-user program, written in python, which shouldn't be tracked as a project dependency and which also shouldn't interact with other python dependencies, using [pipx][]. For me, this means I've installed [tmuxp][], my own tool [SuperTunnel](/2019/11/17/supertunnel.html), [cookiecutter](https://cookiecutter.readthedocs.io/) and [pre-commit](https://pre-commit.com) using [pipx][]. Everything else is really a project dependency, and gets installed in a specific project virtual environment.

# Principles

This can all feel like a bit of a precarious setup -- look away, and you'll find yourself in python dependency hell, or with things that don't work properly. Here are a few principles that I try to keep to make my life easier:

1. I need to be able to run several different versions of python simultaneously, even if I try to do all of my development only on the latest version. At any given time, some projects aren't yet compatible with the latest python release, and the freedom to change versions and upgrade only when I want to is important to me.
2. Every project I work on gets its own virtual envrionment. Even if they are co-dependent, each one gets a separate environment. This means if stuff breaks, I can delete the virtual environment and start again.
3. I make liberal use of `pip install -e .` to install the current directory as a python package. This relies on propertly setting up your projects as python packages, but is a huge help to making things work consistently.
4. End user applications (like [tmuxp][]) should not impact my current project or virtual environment. Their dependencies cloud which dependencies are actually used by my projects, and make things more difficult to isolate and share.
5. Once a python environment is set up, it should be hard for me to mis-use that environment in the future. Thats what I love about `pyenv local` and `.python-version` files in my projects.


`PYTHONPATH` is an escape hatch -- it lets you dynamically add things to python's path on startup. Use it only as an escape hatch, and rely otherwise on your virtual environment and `pip` or `pipenv` to manage installations. If you find yourself having to set `PYTHONPATH` for a project, or for your shell overall, something has gone wrong.

Don't be afraid to use python to debug itself. If you are having trouble with a dependency, using `import numpy; print(numpy.__file__)` can be a great way to figure out what might have gone wrong. Or `import sys; print(sys.path)` if you need to understand where python is looking for modules.

When something does go wrong, spend some time figuring out how to make it work well in the future. I try to not break this setup for small things. For example, if you have a tool which can't find the right python version, I'd rather write a shell script which finds or hard-codes the correct interpreter, than mess with what I've set up above.

# Alternatives

There are many alternatives to all of this -- some are listed below, with a brief note on why I don't use them:

1. Rely on your system package manager to install multiple versions of python (e.g. `brew` or `apt-get`). This is fine, but it can be diffcult to control exactly which version of python you are working against, and even more difficult to run code against 2 different versions of e.g. python3.
2. Use the builtin [venv](https://docs.python.org/3/library/venv.html), or [virtualenv](https://virtualenv.pypa.io/), or [virtualenvwrapper](https://virtualenvwrapper.readthedocs.io/). I've used all of these tools before, but I prefer having pyenv manage all of my python versions in one place.
3. [Conda](https://docs.conda.io/) is a tool for managing lots of aspects of python environments and scientific computing environments. Its a bit simpler than this setup, but can be a bit trickier to customize in my experience, and does some non-standard things (like bundling a lot of common shell tools). Its great for perfectly consistent environments, but heavy handed for my needs, and hard to tune or strip down to just what I want.

Any of these might work for you -- go for it! I'm not saying these tools are bad, just that they aren't in my current arsenal.

---

[^1]: Pull requests welcome in my [dotfiles][]
[^2]: Python2 isn't dead yet, and some places (I'm looking at you, google cloud tools 😒) still haven't ported their work to python3, but rely on a system python interpreter.
[^3]: I use this in projects under source control with git all the time, and so I've added `.python-version` to my list of global git ignores, so that I don't commit my python version preferences. You'll see why this is important (and why python names in `.python-version` aren't necessarily universal) in the [Virtual Environments](#virtual-environments) section.

[homebrew]: https://brew.sh
[dotfiles]: https://github.com/alexrudy/dotfiles
[pyenv]: https://github.com/pyenv/pyenv
[xxenv-latest]: https://github.com/momo-lab/xxenv-latest
[pyenv-virtualenv]: https://github.com/pyenv/pyenv-virtualenv
[pip]: https://pypi.org/project/pip/
[pipenv]: https://pipenv.readthedocs.io/en/latest/
[pipx]: https://github.com/pipxproject/pipx
[poetry]: https://python-poetry.org
[tmuxp]: http://tmuxp.git-pull.com/en/latest/