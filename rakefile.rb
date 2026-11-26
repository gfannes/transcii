task :default do
  sh('rake -T')
end

desc('Install app')
task :install do
  mode = :release
  mode = :debug

  cmd = %w[zig build install --verbose]
  case mode
  when :release then cmd << '--release=fast'
  end
  if (gubg_dir = ENV['gubg'])
    cmd << '--prefix-exe-dir' << "#{gubg_dir}/bin"
  end
  sh(cmd * ' ')
end
