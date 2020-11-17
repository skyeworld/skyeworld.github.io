# GIT

## 参考资料


- [廖雪峰git学习](https://www.liaoxuefeng.com/wiki/0013739516305929606dd18361248578c67b8067c8c017b000)
- [git-scm-book](https://git-scm.com/book/zh/v2)
# Install
```bash
git                        通过git命令是否识别，来检测系统是否安装git
sudo apt-get install git   git的linux安装
```
# 常用命令
git log
git branch
git reset
git checkout
## git stash
```bash
git stash  保存当前工作现场，以供以后使用（可以用于修改一个debug一半时，去修改另一个bug，后又切换至第一个debug）
git stash list 	 查看存储的所有stash
git stash pop    恢复stash内容并删除，等同于以下两个命令 
	git stash apply      恢复
	git stash drop		 删除
```
## git rm
移除文件的版本控制
```bash
git rm --cached -r 文件名
```
## git rebase
合并commit 记录
```
git rebase -i HEAD~3
```
## git merge
```
git checkout master
git pull
# 手动解决冲突
git merge --no-commit
git add <冲突file>
git commit "commit message"

```
## git tag
```bash
git tag -l

git tag v0.1.4

git push origin v0.1.4
```
```bash
git push origin pileTest:pileTest
```
## submodule的使用


- 使用命令直接添加submodule
[参考](https://www.jianshu.com/p/b49741cb1347)



```
$ git submodule add http://10.10.216.46/comleader/dpdk-18.02.2.git dpdk-18.02.2
```


- 查看当前状态



```
$ git status
# On branch master
# Changes to be committed:
#   (use "git reset HEAD <file>..." to unstage)
#
#       new file:   .gitmodules
#       new file:   dpdk-18.02.2
#
```


- 添加子模块



```
# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:43:24] C:1
$ git add -A

# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:43:36] 
$ git commit -m "add dpdk submodule"
[master 1e35a83] add dpdk submodule
 2 files changed, 4 insertions(+)
 create mode 100644 .gitmodules
 create mode 160000 dpdk-18.02.2

# user @ centos7 in /home/nfs/lihao/vpp on git:master o [10:43:59] 
$ git submodule init
```


- submodule修改，提交



```
# user @ centos7 in /home/nfs/lihao/vpp/dpdk-18.02.2 on git:master x [10:47:01] 
$ git add -A 

# user @ centos7 in /home/nfs/lihao/vpp/dpdk-18.02.2 on git:master x [10:47:11] 
$ git commit -m "test submodule"
[master 14f4158] test submodule
 1 file changed, 1 insertion(+), 1 deletion(-)

# user @ centos7 in /home/nfs/lihao/vpp/dpdk-18.02.2 on git:master o [10:47:28] 
$ cd ..

# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:47:31] 
$ git status
# On branch master
# Your branch is ahead of 'origin/master' by 1 commit.
#   (use "git push" to publish your local commits)
#
# Changes not staged for commit:
#   (use "git add <file>..." to update what will be committed)
#   (use "git checkout -- <file>..." to discard changes in working directory)
#
#       modified:   dpdk-18.02.2 (new commits)
#
```


- 提交主工程变更



```
# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:49:24] C:1
$ git add -A

# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:49:27] 
$ git status
# On branch master
# Your branch is ahead of 'origin/master' by 1 commit.
#   (use "git push" to publish your local commits)
#
# Changes to be committed:
#   (use "git reset HEAD <file>..." to unstage)
#
#       modified:   dpdk-18.02.2
#

# user @ centos7 in /home/nfs/lihao/vpp on git:master x [10:49:31] 
$ git commit -m "update dpdk-18.02.2 submodule "
[master e287f68] update dpdk-18.02.2 submodule
 1 file changed, 1 insertion(+), 1 deletion(-)

# user @ centos7 in /home/nfs/lihao/vpp on git:master o [10:50:15] 
$ git push
```


- 更新submodule（两种方式）



1. 主工程目录下执行



```
git submodule foreach git pull
```


2. 更新submodule



```
# user @ centos7 in /home/nfs/lihao/vpp on git:master o [10:52:39] C:1
$ cd dpdk-18.02.2 

# user @ centos7 in /home/nfs/lihao/vpp/dpdk-18.02.2 on git:master o [10:52:46] 
$ git pull
```
