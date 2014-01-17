namespace :monitor do
  namespace :resque do
    task :failures do
      num_failures = Resque::Failure.count
      if num_failures > 0
        Rails.logger.error("#{num_failures} failures in the resque failed queue!")
        ResqueMailer.failed_jobs(num_failures).deliver! # <- bang!
      else
        Rails.logger.info("All clear!")
      end
    end
  end
end
