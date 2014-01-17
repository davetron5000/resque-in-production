# Resque In Production - A Story

To Cover:

- setup/basics
- resque-web
- manual retry
- monitoring
- resque-mailer
- resque-retry
- resque-status
- best practices
- multiple apps
- advanced failure recovery


* Part 1 - problems
  - user registration mailer, takes too long, background it
    + show code
    + show setup
    + show deployment
  - second mailer
    + show code
    + show resque-mailer
  - customer service called about users not getting their signup emails
    + show failed queue
* Part 2 - failure
  - lots of failures - no such ID, TermException, Timeout - OH NO!!!!
  - no such ID
    + someone created a transaction
    + show tradeoffs
    + manual retry
  - TermException
    + retry again?
    + resque-retry
  - let's monitor
* Part 3 - Expert Beginner
  - complex job in several steps, fails on step 2 of N
    - how can we replay this?!
    - have to think hard about our jobs
    - idempotence
    - factor into multiple jobs
  - second application, overloads first one
    - job priority
    - multiple resques
    

  
