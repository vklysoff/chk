# What it is?

Check remote services

## How to start

1. Use sample-files
1. Define remote services in `config_all_monks.pl`
1. Create some TG chat. For example: `someshit`
1. Add bot to TG chat
1. Define bot's TG_TOKEN in `.env`
1. Define TG_CHAT_ID in `.env` by next commands:

    ```bash
    source .env
    curl https://api.telegram.org/${TG_TOKEN}/getUpdates|grep someshit
    ```

1. Run container by command:

    ```bash
    docker compose up -d
    ```

1. You can view log by command:

    ```bash
    docker compose logs chk -ft
    ```
