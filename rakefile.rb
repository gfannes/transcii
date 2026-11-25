task :default do
    sh('rake -T')
end

desc("Install app")
task :install do
    cmd = %w[zig build install --verbose]
    if (gubg_dir = ENV['gubg'])
        cmd << '--prefix-exe-dir' << "#{gubg_dir}/bin"
    end
    sh(cmd*' ')
end
