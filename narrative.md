Once upon a time, Chris was working on the user registration for a web app.  The web
app needed to email users a welcome message after they signed up. And so Chris wrote
the following code:

    class UsersController
      def create
        user = User.new(params[:user])
        if user.save
          UserMailer.welcome(user).deliver
        else
          render 'new'
        end
      end
    end

And it was good.  And Chris' company grew in popularity.  But then Chris noticed that
the signup was getting slower.  And that users were complaining about not getting
their welcome emails more and more often.

Chris noticed that the `UsersController` was taking longer and longer to complete, and
was even timing out on occasion.

Chris decided that if the user didn't have to wait for email to send, the registration
process would complete much more quickly and reliably.  So Chris decided to use Resque
to run the mailer in a background process.  The code part was simple:

    class UsersController
      def create
        user = User.new(params[:user])
        if user.save
          Resque.equene(UserWelcomeMailerJob,user.id)
        else
          render 'new'
        end
      end
    end

    class UserWelcomeMailerJob
      @queue = :mail
      def self.perform(user_id)
        user = User.find(user_id)
        UserMailer.welcome(user).deliver
      end
    end

To get it all to work was a bit trickier.  Chris had to install Redis and configure a
worker to process the job.

Getting Redis installed is pretty easy.  Chris was using Heroku, and set up Redis by
creating an account with a Redis SAAS provider like RedisToGo.  Locally, Chris
installed Redis with homebrew:

    > brew install redis
    > redis > /dev/null 2>&1 &

Getting the worker to run is a bit easier, as there's a worker provided with Resque
that can run in a Rails rake task

    > echo "require 'resque/tasks'" > lib/tasks/resque.rake
    > rake environment resque:work QUEUE=*

Chris was able to set up the worker on the production servers via the application's
`Procfile` (however it would've been simple enough to configure it in other ways if
Chris' environment required something else).

Chris was happily processing emails in the background and it was  easy to setup. Almost too easy.

Sometime later, Pat was having similar problems to Chris, this time, when customers
purchased goods.  The customers get sent a confirmation email, and the
`PurchasesController` was getting slow and timing out.  After talking to Chris, Pat
turned this:

    class PurchasesController
      def create
        customer = current_customer
        purchase = Purchase.new(params[:purchase].merge(customer: customer))
        if purchase.valid?
          Purchase.transaction do
            customer.last_order_date = Time.now
            purchase.save!
            customer.save!
            PurchaseMailer.confirm_purchase(purchase).deliver
          end
        else
          render 'new'
        end
      end
    end

Into this:

    class PurchasesController
      def create
        customer = current_customer
        purchase = Purchase.new(params[:purchase].merge(customer: customer))
        if purchase.valid?
          Purchase.transaction do
            customer.last_order_date = Time.now
            purchase.save!
            customer.save!
            Resque.enqueue(ConfirmPurhaseMailerJob,purchase.id)
          end
        else
          render 'new'
        end
      end
    end

    class ConfirmPurhaseMailerJob
      @queue = :mail
      def self.perform(purchase_id)
        purchase = Purchase.find(purchase_id)
        PurchaseMailer.confirm_purchase(purchase).deliver
      end
    end

By following in Chris' footsteps, Pat was able to fix the most glaring performance
problems in the purchases controller.

During a code review, Danny noticed the similarity with these solutions, and asked if
there was some way to generalize the mailer background jobs so that all new mailers
could take advantage of Resque, as it seemed like it would make sense to just
background the sending of all emails.

Before diving into a software desgin challenge, Chris found resque-mailer, which
defines itself as "A gem plugin which allows messages prepared by ActionMailer to be delivered asynchronously."

Chris curses himself for not seeing this before, but also realizes his good
decision-making in not throwing gems at a problem.  Chris installs resque-mailer:

    gem 'resque_mailer'

And then configures it:

    class PurchaseMailer < ActionMailer::Base
      include Resque::Mailer

       # ...
    end
    class UserMailer < ActionMailer::Base
      include Resque::Mailer

       # ...
    end

The controllers go back to how they were:

    class UsersController
      def create
        user = User.new(params[:user])
        if user.save
          UserMailer.welcome(user).deliver
        else
          render 'new'
        end
      end
    end

    class PurchasesController
      def create
        customer = current_customer
        purchase = Purchase.new(params[:purchase].merge(customer: customer))
        if purchase.valid?
          Purchase.transaction do
            customer.last_order_date = Time.now
            purchase.save!
            customer.save!
            PurchaseMailer.confirm_purchase(purchase).deliver
          end
        else
          render 'new'
        end
      end
    end

And the mailer jobs can be deleted.  And it was good.  When Kelly had to add new code
to mail customers, it was as simple as using a Rails mailer—everything else was taken
care of.

Until Pat got reports that users were *still* not getting their purchase emails.

Pat found no evidence of timeouts from `PurchasesController` but enough customers were
complaining that there *had* to be something wrong.

Pat asked Chris "How do you know what's going on with Resque?" to which Chris answered
"that's a very good question"

Pat and Chris both learned about resque-web, which provides that answer.  Of course,
resque-web wasn't running anywhere, and there wasn't time to set it up as a separate
application, so they decided to mount it within their existing app and re-deploy. 

First, they added this to their `config/routes.rb`:

    constraints CanAccessResque do
      mount Resque::Server, at: 'resque'
    end

The `CanAccessResque` prevents the average user of l33t h4x0r from messing with their
queues, and since they were using CanCan, it was this straightforward:

    class CanAccessResque
      def self.matches?(request)
        if request.session[:user_id].present?
          Ability.new(User.find(request.session[:user_id])).can? :manage, Resque
        else
          false
        end
      end
    end

They also modified their `Ability` class to allow themselves to "manage" resque.

Once they logged in to resque-web, they noticed something they hadn't thought about:
The Failed Queue.  It had a lot of failed jobs in it:

      show resque-web here


So, they replayed the jobs.  But, the jobs still showed up as failed.  Had they failed
again?  They checked their mail provider and, the emails had been sent.  The jobs DID
re-play.  Resque left the jobs in the failed queue.

So they cleared the jobs.  A few hours later, Pat came back to his web browser and
noticed a new job had failed.  He and Chris figured that if they could just automate
the retry, they could keep the mail queueing in the transaciton, where they wanted it,
but not have the jobs fail.

Since resque mailer hid the actual jobs from them, they weren't sure what to do.  Then
they found resque-retry.

    gem 'resque-retry'


    require 'resque-retry'

    # Cribbed from https://blog.engineyard.com/2011/the-resque-way
    class AsyncApplicationMailer < ActionMailer::Base
      include Resque::Mailer
      extend Resque::Plugins::Retry
    end

    class UserMailer < AsyncApplicationMailer

      # ...

    end

In `config/initializers/resque_mailer.rb`

    Resque::Mailer.excluded_environments = [:test]


In the resque setup:


    require 'resque_scheduler'
    require 'resque_scheduler/server'
    require 'resque-retry'
    require 'resque-retry/server'
    require 'resque/failure/redis'
    Resque::Failure::MultipleWithRetrySuppression.classes = [Resque::Failure::Redis]
    Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression

And, finally, because resque-mailer uses resque-scheduler under the covers

    > rake environment resque:scheduler

Whew!  But now, look at it!

(show resque web additions)

And it was good.

Chris and Pat realized that, even though there was a retry setup, they would still
want to know about failed jobs.  It's possible that a legit bug would occur and the
job would fail 5 times.

Unfortunately, there is no resque-monitor, because such a gem would be highly
dependant on their setup.  Fortunately, digging into Resque's API is simple, and they
easily set up a rake task to check:

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

OK!  Now, there's a good thing going.  All the mail jobs are running in the background, retrying as needed, and we've got some solid monitoring that lets us know if there are any failures.
    
A few months later, Chris gets notified that there's a failed job.  He tracks it down
to a job added that handles billing the client when their purchase is ready:

    class PurchaseChargeJob
      @queue = :purchasing
      def self.perform(purchase_id)
        purchase = Purchase.find(purchase_id)
        purchase.capture_authorization!
        purchase.generate_pack_in_materials!
      end
    end

The job failed on `generate_pack_in_materials!`  Which means the customer has been
charged already, which means we cannot replay the job!

Chris realizes that resque jobs have to be idempotent.  Which means that they either
entirely succeed or entirely fail.  He refactors the job into two jobs:

    class PurchaseChargeJob
      @queue = :purchasing
      def self.perform(purchase_id)
        purchase = Purchase.find(purchase_id)
        purchase.capture_authorization!
        Resque.enqueue(PackInMaterialsJob,purchase.id)
      end
    end

    class PackInMaterialsJob 
      @queue = :purchasing
      def self.perform(purchase_id)
        purchase = Purchase.find(purchase_id)
        purchase.generate_pack_in_materials!
      end
    end

Now, if the pack-in materials job fails again, we can simply replay it

    class PackInMaterialsJob 
      extend Resque::Plugins::Retry
      @queue = :purchasing
      @retry_limit = 5
      @retry_delay = 90 #seconds

      def self.perform(purchase_id)
        purchase = Purchase.find(purchase_id)
        purchase.generate_pack_in_materials!
      end
    end

Another crisis averted!

But NOW, Chris finds out that none of the jobs are running at all!  He goes to
resque-web and sees that while mailer jobs, purchasing jobs, and other important jobs
are, in fact, queued, the system is busily processing a new job called
"AdminIndexJob":

    class AdminIndexJob
      @queue = :admin
      def self.perform(customer_id)
        # a whole lot of slow code
        # that builds a cached copy of
        # the customer and all his 
        # or her data
      end
    end

Chris realizes that because our worker is processing every single queue and because
these admin jobs are in a queue that is lexicographically ordered before all the
others, the system is happily handling these jobs without handling the other ones!

Chris realizes that jobs need prioritization.  He could do this:

    > rake environment resque:work QUEUE=mail,purchasing,admin

But we can't have purchasing jobs fall behind if there's a sudden influx of new users.
he could do this:

    > rake environment resque:work QUEUE=mail,purchasing,admin
    > rake environment resque:work QUEUE=purchasing,mail,admin

This gets confusing, especially as the number of queues and jobs grow.  Instead, Chris
decided the simplest thing to do is to give each queue its own worker

    > rake environment resque:work QUEUE=mail
    > rake environment resque:work QUEUE=purchasing
    > rake environment resque:work QUEUE=admin

And all was well, yet again.  Until there was a complete disaster two months later.

The application was raise errors when trying  to _queue_ jobs!  Redis was out of
space.

Chris fired up resque-web and saw a ton of jobs in a new queue called "analytics".
Checking his application configuration, there was no worker configured to monitor that
queue, however it contained thousands of jobs that were seemingly being processed.

It turns out that the business intelligence team was using resque to help organize
their jobs, and copied the configuration of the main application, thus using the same
redis that the production app was using.

Chris quickly stopped the analytics worker to let the production workers catch up.  He
and Jo from BI realized that the BI tasks should not have the ability to take down
production, even under times of great stress.  So, they set up a new resque on a new
redis, so that no matter what happened in analytics-land, the production application
would not be impacted.

A few months later, Chris was in a new job, as the first developer at a new startup.
Armed with his knowledge and experience with Resque, he spent a few extra hours
setting things up:

* All external contact would be run in a job
* All email would be sent in a job
* All jobs would be configured to retry
* All jobs would be idempotent
* Each queue would have its own worker
* Each app would have its own redis
* Everything would be monitored
