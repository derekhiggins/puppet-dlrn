require 'spec_helper'

describe 'delorean::worker' do
  let :facts do
  {   :osfamily               => 'RedHat',
      :operatingsystem        => 'Fedora',
      :operatingsystemrelease => '24',
      :concat_basedir         => '/tmp',
      :puppetversion          => '3.7.0',
      :sudoversion            => '1.8.15',
      :processorcount         => 2 }
  end

  let :params do { 
    :distro         => 'centos7',
    :target         => 'centos',
    :distgit_branch => 'rpm-master',
    :distro_branch  => 'master',
    :disable_email  => true,
    :enable_cron    => false,
    }
  end


  context 'with default parameters' do
    ['fedora-master', 'centos-master', 'centos-liberty'].each do |user|
      describe "when user is #{user}" do
        let :title do
          user
        end

        it 'creates user' do
          is_expected.to contain_user("#{user}").with(
            :groups     => ['users','mock'],
            :uid        => nil,
            :managehome => 'true',
          )
        end 

        it 'sets owner on home directory' do
          is_expected.to contain_file("/home/#{user}").with(
            :ensure => 'directory',
            :mode   => '0755',
            :owner  => "#{user}",
          ).with_before(/Exec\[ensure home contents belong to #{user}\]/)
        end

        it 'creates the data directory' do
          is_expected.to contain_file("/home/#{user}/data").with(
            :ensure  => 'directory',
            :mode    => '0755',
            :owner   => "#{user}",
          ).with_before(/File\[\/home\/#{user}\/data\/repos\]/)
        end

        it 'creates the data/repos directory' do
          is_expected.to contain_file("/home/#{user}/data/repos").with(
            :ensure  => 'directory',
            :mode => '0755',
            :owner   => "#{user}",
          ).with_before(/File\[\/home\/#{user}\/data\/repos\/delorean-deps.repo\]/)
        end

        it 'creates the delorean-deps.repo file' do
          is_expected.to contain_file("/home/#{user}/data/repos/delorean-deps.repo").with(
            :source => "puppet:///modules/delorean/#{user}-delorean-deps.repo",
            :mode   => '0644',
            :owner  => "#{user}",
            :group  => "#{user}",
          )
        end

        it 'creates the sudo entry' do
          is_expected.to contain_sudo__conf("#{user}").with(
            :priority => '10',
            :content  => "#{user} ALL=(ALL) NOPASSWD: /bin/rm",
          )
        end

        it 'creates a logrotate entry' do
          is_expected.to contain_file("/etc/logrotate.d/delorean-#{user}")
        end

        it 'configures the venv' do
          is_expected.to contain_file("/home/#{user}/setup_delorean.sh").with(
            :ensure  => 'present',
            :mode    => '0755',
          )
          is_expected.to contain_exec("pip-install-#{user}").with(
            :command => "/home/#{user}/setup_delorean.sh",
            :cwd     => "/home/#{user}/delorean",
            :creates => "/home/#{user}/.venv/bin/delorean",
          )
        end

        it { is_expected.not_to contain_cron("#{user}") }
        it 'does not set smtpserver in projects.ini' do
          is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
          .with_content(/smtpserver=$/)
        end

        it 'sets the default release in projects.ini' do
            is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
            .with_content(/tags=mitaka$/)
        end

        it 'does not set a gerrit user in projects.ini' do
            is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
            .with_content(/gerrit=$/)
        end
      end

      context 'with specific uid' do
        before :each do
          params.merge!(:uid => '1001')
        end

        let :title do
          user
        end

        it 'creates user with defined uid' do
          is_expected.to contain_user("#{user}").with(
            :uid => '1001'
          )
        end
      end

      context 'with enabled cron job' do
        before :each do
          params.merge!(:enable_cron => true)
        end

        let :title do
          user
        end

        it 'creates cron job' do
          is_expected.to contain_cron("#{user}").with(
            :command => '/usr/local/bin/run-delorean.sh',
            :user    => "#{user}",
            :hour    => '*',
            :minute  => '*/5',
          )
        end
      end

      context 'with enabled emails' do
        before :each do
          params.merge!(:disable_email => false)
        end

        let :title do
          user
        end

        it 'sets smtpserver in projects.ini' do
            is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
            .with_content(/smtpserver=localhost$/)
        end
      end

      context 'with symlinks' do
        before :each do
          params.merge!(:symlinks => ['/var/www/html/f24','/var/www/html/fedora24'])
        end

        let :title do
          user
        end

        it 'creates symlinks' do
          is_expected.to contain_file('/var/www/html/f24').with(
            :ensure  => 'link',
            :target  => "/home/#{user}/data/repos",
            :require => 'Package[httpd]',
          )
        end
      end

      context 'when specifying release' do
        before :each do
          params.merge!(:release => 'liberty')
        end

        let :title do
          user
        end

        it 'sets tags in projects.ini' do
            is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
            .with_content(/tags=liberty$/)
        end
      end

      context 'when setting a gerrit user' do
        before :each do
          params.merge!(:gerrit_user => 'foo')
        end

        let :title do
          user
        end

        it 'sets a gerrit user in projects.ini' do
            is_expected.to contain_file("/usr/local/share/delorean/#{user}/projects.ini")
            .with_content(/gerrit=yes$/)
        end

        it 'configures the gerrit user' do
          is_expected.to contain_exec("Set gerrit user for #{user}").with(
            :command => "git config --global --add gitreview.username foo",
            :require => "File[/home/#{user}]",
          )

          is_expected.to contain_exec("Set git user for #{user}").with(
            :command => "git config --global user.name foo",
            :require => "File[/home/#{user}]",
          )

          is_expected.to contain_exec("Set git email for #{user}").with(
            :command => "git config --global user.email foo@rdoproject.org",
            :require => "File[/home/#{user}]",
          )
        end
      end
    end
  end


  context 'with special case for fedora-rawhide-master ' do
    let :title do
      'fedora-rawhide-master'
    end

    it 'creates specific mock config file for rawhide' do
      is_expected.to contain_file('/home/fedora-rawhide-master/delorean/scripts/fedora-rawhide.cfg').with(
        :source => 'puppet:///modules/delorean/fedora-rawhide.cfg',
        :mode   => '0644',
        :owner  => 'fedora-rawhide-master',
      )
    end
  end

  context 'when running on master' do
    let :title do
      'centos-master'
    end

    it 'sets proper baseurl in projects.ini' do
        is_expected.to contain_file("/usr/local/share/delorean/centos-master/projects.ini")
        .with_content(/baseurl=http:\/\/trunk.rdoproject.org\/centos7$/)
    end
  end

  context 'with special case for centos-kilo' do
    before :each do
      params.merge!(:release       => 'kilo')
      params.merge!(:target        => 'centos-kilo')
      params.merge!(:distro_branch => 'stable/kilo')
    end

    let :title do
      'centos-kilo'
    end

    it 'creates specific mock config file for centos-kilo' do
      is_expected.to contain_file('/home/centos-kilo/delorean/scripts/centos-kilo.cfg')
      .with_content(/config_opts\[\'root\'\] = \'delorean-centos-kilo-x86_64\'/)
    end

    it 'creates directory under /var/www/html' do
      is_expected.to contain_file('/var/www/html/centos-kilo').with(
        :ensure  => 'directory',
        :mode    => '0755',
        :path    => '/var/www/html/kilo',
        :require => 'Package[httpd]',
      )
    end

    it 'sets proper baseurl in projects.ini' do
        is_expected.to contain_file("/usr/local/share/delorean/centos-kilo/projects.ini")
        .with_content(/baseurl=http:\/\/trunk.rdoproject.org\/centos7-kilo$/)
    end
  end
end

