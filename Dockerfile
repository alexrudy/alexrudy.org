FROM nginx

# Ruby
RUN apt-get -y update
RUN apt-get -y install ruby ruby-dev build-essential nodejs

# Jekyll
RUN gem install jekyll bundler

# Environment
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

ADD . /src/jekyll-site
WORKDIR /src/jekyll-site
RUN bundler exec jekyll build
RUN cp -r /src/jekyll-site/_site/* /usr/share/nginx/html