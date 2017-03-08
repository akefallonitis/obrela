FROM docker.elastic.co/logstash/logstash:5.2.2
RUN logstash-plugin install logstash-output-syslog
RUN logstash-plugin install logstash-output-tcp
RUN logstash-plugin install logstash-output-udp
ADD /logstash-input-azuretablemulti /plugins/logstash-input-azuretablemulti
RUN logstash-plugin install /plugins/logstash-input-azuretablemulti/logstash-input-azuretablemulti-1.0.0.gem
ADD /logstash-input-azureblobmulti /plugins/logstash-input-azureblobmulti
RUN logstash-plugin install /plugins/logstash-input-azureblobmulti/logstash-input-azureblobmulti-0.9.5.gem
ADD /logstash-output-cefgen /plugins/logstash-output-cefgen
RUN logstash-plugin install /plugins/logstash-output-cefgen/logstash-output-cefgen-0.1.0.gem
ADD /logstash-output-cefwinhelper /plugins/logstash-output-cefwinhelper
RUN logstash-plugin install /plugins/logstash-output-cefwinhelper/logstash-output-cefwinhelper-0.1.0.gem
RUN logstash-plugin remove x-pack
RUN logstash-plugin install logstash-filter-translate
