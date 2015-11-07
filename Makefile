deploy:
	@hexo generate
	@ls ../moonshadow.github.io | grep -v '.git'|grep -v CNAME |xargs rm -rf && cp -rf public/* ../moonshadow.github.io
	@cd ../moonshadow.github.io &&  git add . && git commit -m'update site' && git push origin master
	@git add .
	@git commit -m'update site'
	@git push origin master
