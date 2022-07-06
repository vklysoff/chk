# What it is?

Check remote services

## How to start

1. Use sample-files
2. Create some TG chat. For example: someshit.
3. Define TG_TOKEN

  ```bash
  source .env
  curl https://api.telegram.org/${TG_TOKEN}/getUpdates|grep someshit
  ```
