# Linux_health_monitor
 Linux Health Monitor - Quick Setup
 This tool monitors your CPU, RAM, disk, network, and updates and sends alerts to your email if something goes wrong.
 Why sendemail?
Linux does not send email alerts out of the box.
sendemail is a lightweight CLI tool that allows your scripts to send alerts via Gmail SMTP, notifying you immediately if your system needs attention.
though it's not perfect yet i'm still working on it 

1.  Install sendemail

```sudo apt update```
```sudo apt install sendemail libnet-ssleay-perl libio-socket-ssl-perl ```

2. Create a Gmail App Password
Go to `https://myaccount.google.com/apppasswords`
Ensure 2FA is enabled.
Generate an App Password/passkey for “Mail” on “Other” (Custom name like system_monitor).
Copy the generated 16-character app password.

3. Set Environment Variables
Add the following to your ~/.zshrc or ~/.bashrc (replace with your values):
```
# System Health Monitor Email Config
export SMTP_USER="monitoringbot2025@gmail.com" #  create an email for your machine
export SMTP_PASS="your-app-password" # generated from  your machine email
export EMAIL_RECIPIENT="yourpersonal@gmail.com"  # Where you want to receive alerts, 
```
Reload your environment:
`source ~/.zshrc   # or ~/.bashrc if you use Bash`
 then run script , make sure it's executable before you run it 
 you can also automate it with cron

