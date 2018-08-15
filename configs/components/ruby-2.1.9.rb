component "ruby-2.1.9" do |pkg, settings, platform|
  pkg.version "2.1.9"
  pkg.md5sum "d9d2109d3827789344cc3aceb8e1d697"

  # rbconfig-update is used to munge rbconfigs after the fact.
  pkg.add_source("file://resources/files/rbconfig-update.rb")

  # PDK packages multiple rubies and we need to tweak some settings
  # if this is not the *primary* ruby.
  if (pkg.get_version != settings[:ruby_version])
    # not primary ruby

    # ensure we have config for this ruby
    unless settings.has_key?(:additional_rubies) && settings[:additional_rubies].has_key?(pkg.get_version)
      raise "missing config for additional ruby #{pkg.get_version}"
    end

    ruby_settings = settings[:additional_rubies][pkg.get_version]

    ruby_dir = ruby_settings[:ruby_dir]
    ruby_bindir = ruby_settings[:ruby_bindir]
    host_ruby = ruby_settings[:host_ruby]
  else
    # primary ruby
    ruby_dir = settings[:ruby_dir]
    ruby_bindir = settings[:ruby_bindir]
    host_ruby = settings[:host_ruby]
  end

  # Most ruby configuration happens in the base ruby config:
  instance_eval File.read('configs/components/_base-ruby.rb')
  # Configuration below should only be applicable to ruby 2.1.9

  #########
  # PATCHES
  #########

  base = 'resources/patches/ruby_219'
  pkg.apply_patch "#{base}/libyaml_cve-2014-9130.patch"

  # Patches from Ruby 2.4 security fixes. See the description and
  # comments of RE-9323 for more details.
  pkg.apply_patch "#{base}/cve-2017-0898.patch"
  pkg.apply_patch "#{base}/cve-2017-10784.patch"
  pkg.apply_patch "#{base}/cve-2017-14033.patch"
  pkg.apply_patch "#{base}/cve-2017-14064.patch"
  pkg.apply_patch "#{base}/cve-2017-17405.patch"

  # Patches from Ruby 2.2.10 security fixes from March 2018. See
  # RE-10480 for more details.
  pkg.apply_patch "#{base}/cve-2018-8780.patch"
  pkg.apply_patch "#{base}/cve-2018-6914.patch"
  pkg.apply_patch "#{base}/cve-2018-8779.patch"
  pkg.apply_patch "#{base}/cve-2018-8778.patch"
  pkg.apply_patch "#{base}/cve-2018-8777-1.patch"
  pkg.apply_patch "#{base}/cve-2018-8777-2.patch"
  pkg.apply_patch "#{base}/cve-2017-17742.patch"

  if platform.is_aix?
    pkg.apply_patch "#{base}/aix_ruby_2.1_libpath_with_opt_dir.patch"
    pkg.apply_patch "#{base}/aix_ruby_2.1_fix_proctitle.patch"
    pkg.apply_patch "#{base}/aix_ruby_2.1_fix_make_test_failure.patch"
    pkg.apply_patch "#{base}/Remove-O_CLOEXEC-check-for-AIX-builds.patch"
  end

  if platform.is_windows?
    pkg.apply_patch "#{base}/windows_ruby_2.1_update_to_rubygems_2.4.5.patch"
    pkg.apply_patch "#{base}/windows_ruby_2.1_fixup_generated_batch_files.patch"
    pkg.apply_patch "#{base}/windows_remove_DL_deprecated_warning.patch"
    pkg.apply_patch "#{base}/windows_ruby_2.1_update_to_rubygems_2.4.5.1.patch"
    pkg.apply_patch "#{base}/windows_ruby_2.1_update_rbinstall.patch"
    pkg.apply_patch "#{base}/windows_rubygems_cve_2017_0902_0899_0900_0901.patch"
  else
    pkg.apply_patch "#{base}/rubygems_cve_2017_0902_0899_0900_0901.patch"
  end

  ####################
  # ENVIRONMENT, FLAGS
  ####################

  special_flags = " --prefix=#{ruby_dir} --with-opt-dir=#{settings[:prefix]} "

  if platform.is_aix?
    # This normalizes the build string to something like AIX 7.1.0.0 rather
    # than AIX 7.1.0.2 or something
    special_flags += " --build=#{settings[:platform_triple]} "
  elsif platform.is_solaris? && platform.architecture == "sparc"
    special_flags += " --with-baseruby=#{host_ruby} "
  elsif platform.is_cross_compiled_linux?
    special_flags += " --with-baseruby=#{host_ruby} "
  elsif platform.is_windows?
    special_flags = " CPPFLAGS='-DFD_SETSIZE=2048' debugflags=-g --prefix=#{ruby_dir} --with-opt-dir=#{settings[:prefix]} "
  end

  ###########
  # CONFIGURE
  ###########

  # Here we set --enable-bundled-libyaml to ensure that the libyaml included in
  # ruby is used, even if the build system has a copy of libyaml available
  pkg.configure do
    [
      "bash configure \
        --enable-shared \
        --enable-bundled-libyaml \
        --disable-install-doc \
        --disable-install-rdoc \
        #{settings[:host]} \
        #{special_flags}"
     ]
  end

  #########
  # INSTALL
  #########
  target_doubles = {
    'powerpc-ibm-aix6.1.0.0' => 'powerpc-aix6.1.0.0',
    'aarch64-redhat-linux' => 'aarch64-linux',
    'ppc64le-redhat-linux' => 'powerpc64le-linux',
    'powerpc64le-suse-linux' => 'powerpc64le-linux',
    'powerpc64le-linux-gnu' => 'powerpc64le-linux',
    's390x-linux-gnu' => 's390x-linux',
    'i386-pc-solaris2.10' => 'i386-solaris2.10',
    'sparc-sun-solaris2.10' => 'sparc-solaris2.10',
    'i386-pc-solaris2.11' => 'i386-solaris2.11',
    'sparc-sun-solaris2.11' => 'sparc-solaris2.11',
    'arm-linux-gnueabihf' => 'arm-linux-eabihf',
    'arm-linux-gnueabi' => 'arm-linux-eabi',
    'x86_64-w64-mingw32' => 'x64-mingw32',
    'i686-w64-mingw32' => 'i386-mingw32'
  }
  if target_doubles.has_key?(settings[:platform_triple])
    rbconfig_topdir = File.join(ruby_dir, 'lib', 'ruby', '2.1.0', target_doubles[settings[:platform_triple]])
  else
    rbconfig_topdir = "$$(#{settings[:ruby_bindir]}/ruby -e \"puts RbConfig::CONFIG[\\\"topdir\\\"]\")"
  end

  rbconfig_changes = {}
  if platform.is_aix?
    rbconfig_changes["CC"] = "gcc"
  elsif platform.name =~ /el-7-ppc64le/
    rbconfig_changes["CC"] = "gcc"
    # EL 7 on POWER will fail with -Wl,--compress-debug-sections=zlib so this
    # will remove that entry
    rbconfig_changes["DLDFLAGS"] = "-Wl,-rpath=/opt/puppetlabs/puppet/lib -L/opt/puppetlabs/puppet/lib  -Wl,-rpath,/opt/puppetlabs/puppet/lib"
  elsif platform.is_cross_compiled? || platform.is_solaris?
    rbconfig_changes["CC"] = "gcc"
    rbconfig_changes["warnflags"] = "-Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long -Wno-missing-field-initializers -Wno-tautological-compare -Wno-parentheses-equality -Wno-constant-logical-operand -Wno-self-assign -Wunused-variable -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat -Wsuggest-attribute=noreturn -Wsuggest-attribute=format -Wno-maybe-uninitialized"
    if platform.name =~ /el-7-ppc64le/
      # EL 7 on POWER will fail with -Wl,--compress-debug-sections=zlib so this
      # will remove that entry
      rbconfig_changes["DLDFLAGS"] = "-Wl,-rpath=/opt/puppetlabs/puppet/lib -L/opt/puppetlabs/puppet/lib  -Wl,-rpath,/opt/puppetlabs/puppet/lib"
    end
  elsif platform.is_windows?
    rbconfig_changes["CC"] = "x86_64-w64-mingw32-gcc"
  end

  unless rbconfig_changes.empty?
    pkg.install do
      [
        "#{settings[:host_ruby]} ../rbconfig-update.rb \"#{rbconfig_changes.to_s.gsub('"', '\"')}\" #{rbconfig_topdir}",
        "cp original_rbconfig.rb #{settings[:datadir]}/doc/rbconfig-2.1.9-orig.rb",
        "cp new_rbconfig.rb #{rbconfig_topdir}/rbconfig.rb",
      ]
    end
  end
end
