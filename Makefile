deploy:
	@hexo generate
	@cp -rf public/* ../moonshadow.github.io
	@cd ../moonshadow.github.io
	@git add .
	@git commit -m'update site'
	@git push -f origin master
	@cd ../vita.lol
