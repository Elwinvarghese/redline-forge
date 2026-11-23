# Deployment

Install Docker and Compose on an isolated target VM, copy the `redline-forge` directory, then run `docker compose up --build -d`. Expose only port 8080 through the VM's lab network. Do not publish the PostgreSQL service. Snapshot the VM after a verified reset for learner distribution.
