FROM  local/thruk-labs-rocky:nightly

COPY playbook.yml /root/ansible_dropin/
ENV  ANSIBLE_ROLES_PATH=/thruk/t/scenarios/_common/ansible/roles
COPY test.cfg /root/
COPY thruk_cluster.conf /root/
COPY dot_thruk /root/
COPY 1.tbp /root/
COPY 1.rpt /root/
COPY 1.tsk /root/
