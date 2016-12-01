{%- from "grafana/map.jinja" import client with context %}
{%- if client.get('enabled', False) %}

/etc/salt/minion.d/_grafana.conf:
  file.managed:
  - source: salt://grafana/files/_grafana.conf
  - template: jinja
  - user: root
  - group: root

{%- for datasource_name, datasource in client.datasource.iteritems() %}

Run the curl POST to create the datasource:
  cmd.run:
    - name: |
        curl -i -X POST 'http://{{ pillar.grafana.server.admin.user }}:{{ pillar.grafana.server.admin.password }}@{{ pillar.grafana.client.server.host }}:{{ pillar.grafana.client.server.port }}/api/datasources' -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"{{datasource_name}}","type":"{{datasource.type}}","id":"{{datasource.id}}","access":"proxy", "url":"{{datasource.url}}","password":"{{datasource.password}}","user":"{{datasource.user}}", "database":"{{datasource.database}}","basicAuth":true,"basicAuthUser":"{{datasource.basic_auth_user}}", "basicAuthPassword":"{{datasource.basic_auth_password}}","isDefault":true,"jsonData":null}'

# automating datasource creation isn't working...but it might be better than my cmd.run hack above
# leaving this in for now in case we can get it working later
#grafana_client_datasource_{{ datasource_name }}:
#  grafana3_datasource.present:
#  - name: {{ datasource_name }}
#  - type: {{ datasource.type }}
#  - url: http://{{ datasource.host }}:{{ datasource.get('port', 80) }}
#  {%- if datasource.access is defined %}
#  - access: proxy
#  {%- endif %}
#  {%- if datasource.user is defined %}
#  - user: {{ datasource.user }}
#  - password: {{ datasource.password }}
#  {%- endif %}
#  {%- if datasource.get('is_default', False) %}
#  - is_default: {{ datasource.is_default|lower }}
#  {%- endif %}
#  {%- if datasource.database is defined %}
#  - database: {{ datasource.database }}
#  {%- endif %}
#  {%- if datasource.basic_auth is defined %}
#  - basic_auth: {{ datasource.basic_auth }}
#  {%- endif %}
#  {%- if datasource.basic_auth_user is defined %}
#  - basic_auth_user: {{ datasource.basic_auth_user }}
#  {%- endif %}
#  {%- if datasource.basic_auth_password is defined %}
#  - basic_auth_password: {{ datasource.basic_auth_password }}
#  {%- endif %}

{%- endfor %}

{%- set raw_dict = {} %}
{%- set final_dict = {} %}

{%- if client.remote_data.engine == 'salt_mine' %}
{%- for node_name, node_grains in salt['mine.get']('*', 'grains.items').iteritems() %}
  {%- if node_grains.grafana is defined %}
  {%- set raw_dict = salt['grains.filter_by']({'default': raw_dict}, merge=node_grains.grafana.get('dashboard', {})) %}
  {%- endif %}
{%- endfor %}
{%- endif %}

{%- if client.dashboard is defined %}
  {%- set raw_dict = salt['grains.filter_by']({'default': raw_dict}, merge=client.dashboard) %}
{%- endif %}

{%- for dashboard_name, dashboard in raw_dict.iteritems() %}
  {%- if dashboard.get('format', 'yaml')|lower == 'yaml' %}
  # Dashboards in JSON format are considered as blob
  {%- set rows = [] %}
  {%- for row_name, row in dashboard.get('row', {}).iteritems() %}
    {%- set panels = [] %}
    {%- for panel_name, panel in row.get('panel', {}).iteritems() %}
      {%- set targets = [] %}
      {%- for target_name, target in panel.get('target', {}).iteritems() %}
        {%- do targets.extend([target]) %}
      {%- endfor %}
      {%- do panel.update({'targets': targets}) %}
      {%- do panels.extend([panel]) %}
    {%- endfor %}
    {%- do row.update({'panels': panels}) %}
    {%- do rows.extend([row]) %}
  {%- endfor %}
  {%- do dashboard.update({'rows': rows}) %}
  {%- endif %}

  {%- do final_dict.update({dashboard_name: dashboard}) %}
{%- endfor %}

{%- for dashboard_name, dashboard in final_dict.iteritems() %}
  {%- if dashboard.get('enabled', True) %}
grafana_client_dashboard_{{ dashboard_name }}:
  grafana3_dashboard.present:
  - name: {{ dashboard_name }}
    {%- if dashboard.get('format', 'yaml')|lower == 'json' %}
    {%- import_json dashboard.template as dash %}
  - dashboard: {{ dash|json }}
  - dashboard_format: json
    {%- else %}
  - dashboard: {{ dashboard }}
    {%- endif %}
  {%- else %}
grafana_client_dashboard_{{ dashboard_name }}:
  grafana3_dashboard.absent:
  - name: {{ dashboard_name }}
  {%- endif %}
{%- endfor %}

{%- endif %}
