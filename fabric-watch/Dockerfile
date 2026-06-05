FROM grafana/grafana:11.3.0

USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY provisioning /etc/grafana/provisioning
USER grafana

ENTRYPOINT ["/entrypoint.sh"]
