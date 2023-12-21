@echo off
for /f "tokens=*" %%a in ('wmic product where "name like '%%Google Chrome%%'" call uninstall /nointeractive') do echo %%a