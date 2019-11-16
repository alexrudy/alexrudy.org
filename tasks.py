from invoke import task
import sys


@task
def setup(c):
    c.run("gem install bundler jekyll")


@task(setup)
def build(c):
    c.run("bundle exec jekyll build")


@task
def serve(c):
    c.run("bundle exec jekyll serve")
