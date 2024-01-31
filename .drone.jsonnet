local docker_pipeline = {
  kind: 'pipeline',
  type: 'docker',
};

local default_trigger = {
  trigger: {
    event: [
      'custom',
      'pull_request',
      'push',
    ],
  },
};

local platform(arch) = {
  platform: {
    os: 'linux',
    arch: arch,
  },
};

local git_reset_debian = [
  |||
    bash -c 'export CODENAME=`lsb_release -c -s` && export COMMIT_HASH=`dpkg-query -W rspamd | sed "s/~$${CODENAME}//g" | sed "s/.*~//g"` && cd $DRONE_WORKSPACE/rspamd && git reset --hard $${COMMIT_HASH}'
  |||,
];

local git_reset_el = [
  |||
    bash -c 'cd $DRONE_WORKSPACE/rspamd && COMMIT_HASH=`rpm -q rspamd | sed 's/rspamd-//g' | sed 's/-.*//g'` && git reset --hard $${COMMIT_HASH}'
  |||,
];

local install_epel(family, epel_version) = [
  local extra_step = if family != 'oraclelinux' && epel_version == '9' then 'dnf -y install "dnf-command(config-manager)" && dnf config-manager --set-enabled crb' else if family != 'oraclelinux' && epel_version == '8' then 'dnf -y install "dnf-command(config-manager)" && dnf config-manager --set-enabled powertools' else '';
  extra_step,
  if epel_version == '7' then 'yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm' else 'dnf -y install epel-release',
];

local install_rspamd_el(el_version) = [
  'curl https://rspamd.com/rpm-stable/centos-' + el_version + '/rspamd.repo > /etc/yum.repos.d/rspamd.repo',
  'yum -y install rspamd',
];

local install_rspamd_debian = [
  'apt-get update',
  'apt-get install -y lsb-release wget gpg',
  'mkdir -p /etc/apt/keyrings',
  'wget -O- https://rspamd.com/apt-stable/gpg.key | gpg --dearmor > /etc/apt/keyrings/rspamd.gpg',
  'echo "deb [signed-by=/etc/apt/keyrings/rspamd.gpg] http://rspamd.com/apt-stable/ `lsb_release -c -s` main" > /etc/apt/sources.list.d/rspamd.list',
  'apt-get update',
  'apt-get --no-install-recommends install -y rspamd',
];

local test_deps_debian(family, codename) = [
  local miltertest = if family == 'ubuntu' && codename == 'focal' then '' else 'miltertest ';
  'apt-get install -y git ' + miltertest + 'python3 python3-dev python3-pip python3-venv redis-server',
];

local test_deps_el = [
  'yum -y install gcc git python3 python3-devel python3-pip redis',
];

local test_preparation_generic = [
  'python3 -mvenv $DRONE_WORKSPACE/venv',
  'bash -c "source $DRONE_WORKSPACE/venv/bin/activate && pip3 install --no-cache --disable-pip-version-check --no-binary :all: setuptools==57.5.0"',  // https://github.com/dmeranda/demjson/issues/43
  'bash -c "source $DRONE_WORKSPACE/venv/bin/activate && pip3 install --no-cache --disable-pip-version-check --no-binary :all: demjson psutil requests==2.27.1 robotframework==6.1.1 tornado==6.1"',
  'git clone https://github.com/rspamd/rspamd.git',
];

local run_tests_generic(family, codename) = [
  local exclude_milter = if (family == 'ubuntu' && codename == 'focal') || family == 'oraclelinux' then '--exclude milter ' else '';
  local var_rspamd_group = if family != 'debian' && family != 'ubuntu' then '--variable RSPAMD_GROUP:nobody ' else '';
  'RSPAMD_INSTALLROOT=/usr bash -c "source $DRONE_WORKSPACE/venv/bin/activate && umask 0000 && robot ' + var_rspamd_group + '--removekeywords wuks --exclude isbroken ' + exclude_milter + '$DRONE_WORKSPACE/rspamd/test/functional/cases"',
];

local debian_pipeline(family, codename, arch) = {
  name: std.format('%s_%s_%s', [family, codename, arch]),
  steps: [
    {
      name: 'test',
      image: std.format('%s:%s', [family, codename]),
      commands: install_rspamd_debian + test_deps_debian(family, codename) + test_preparation_generic + git_reset_debian + run_tests_generic(family, codename),
    },
  ],
} + platform(arch) + default_trigger + docker_pipeline;

local el_pipeline(family, el_version, arch) = {
  name: std.format('%s_%s_%s', [family, el_version, arch]),
  steps: [
    {
      name: 'test',
      image: std.format('%s:%s', [family, el_version]),
      commands: install_epel(family, el_version) + install_rspamd_el(el_version) + test_deps_el + test_preparation_generic + git_reset_el + run_tests_generic(family, el_version),
    },
  ],
} + platform(arch) + default_trigger + docker_pipeline;


[
  debian_pipeline('debian', 'bookworm', 'amd64'),
  debian_pipeline('debian', 'bookworm', 'arm64'),
  debian_pipeline('debian', 'bullseye', 'amd64'),
  debian_pipeline('debian', 'bullseye', 'arm64'),
  debian_pipeline('ubuntu', 'focal', 'amd64'),
  debian_pipeline('ubuntu', 'focal', 'arm64'),
  debian_pipeline('ubuntu', 'jammy', 'amd64'),
  debian_pipeline('ubuntu', 'jammy', 'arm64'),
  el_pipeline('oraclelinux', '7', 'amd64'),
  el_pipeline('oraclelinux', '7', 'arm64'),
  el_pipeline('oraclelinux', '8', 'amd64'),
  el_pipeline('oraclelinux', '8', 'arm64'),
  el_pipeline('oraclelinux', '9', 'amd64'),
  el_pipeline('oraclelinux', '9', 'arm64'),
  el_pipeline('almalinux', '8', 'amd64'),
  el_pipeline('almalinux', '8', 'arm64'),
  el_pipeline('almalinux', '9', 'amd64'),
  el_pipeline('almalinux', '9', 'arm64'),
  el_pipeline('rockylinux', '8', 'amd64'),
  el_pipeline('rockylinux', '8', 'arm64'),
  el_pipeline('rockylinux', '9', 'amd64'),
  el_pipeline('rockylinux', '9', 'arm64'),
  {
    kind: 'signature',
    hmac: '0000000000000000000000000000000000000000000000000000000000000000',
  },
]
