FROM docker.elastic.co/logstash/logstash:5.2.2
RUN logstash-plugin install logstash-output-syslog
RUN logstash-plugin install logstash-output-tcp
RUN logstash-plugin install logstash-output-udp
