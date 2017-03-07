FROM docker.elastic.co/logstash/logstash:5.2.2
RUN logstash-plugin install logstash-output-syslog
RUN logstash-plugin install logstash-output-tcp
RUN logstash-plugin install logstash-output-udp
RUN apt-get update && apt-get install -y \
    git\
    gem\
    curl
RUN curl -k -L get.rvm.io | bash -s stable
RUN source /etc/profile.d/rvm.sh
RUN rvm install jruby
RUN useradd developer
RUN passwd developer
RUN usermod -g rvm developer
RUN su - developer
RUN rvm -v
RUN rvm jruby
RUN gem install bundler
RUN gem install rspec
RUN exit
ADD /logstash-input-azuretablemulti /home/developer/logstash-input-azuretablemulti
RUN cd /home/developer/logstash-input-azuretablemulti
RUN logstash-plugin install logstash-input-azuretablemulti-1.0.0.gem
ADD /logstash-output-cefgen /home/developer/logstash-output-cefgen
RUN /home/developer/logstash-output-cefgen
RUN logstash-plugin install logstash-output-cefgen-0.1.0.gem
ADD /logstash-output-cefwinhelper /home/developer/logstash-output-cefwinhelper
RUN logstash-plugin install logstash-output-cefwinhelper-0.1.0.gem
