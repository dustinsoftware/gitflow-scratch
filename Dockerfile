FROM mcr.microsoft.com/dotnet/core/sdk:3.0 AS build

WORKDIR /app

COPY . .

RUN git config --global user.email "you@example.com"
RUN git config --global user.name "Your Name"

WORKDIR /git-upstream

RUN git init .
RUN touch ./README.md
RUN git add README.md
RUN git commit -m "First commit"
RUN git config --bool core.bare true

WORKDIR /git-directory

RUN git clone /git-upstream/.git .

RUN git push --set-upstream origin master
RUN git checkout -b develop
RUN git push --set-upstream origin develop

ENV CI=1

# Typical workflow
FROM build
RUN echo 'typical workflow'

RUN echo hi >> README.md

RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100
RUN pwsh /app/release.ps1 -mark_released -version 100

RUN pwsh /app/assertOutput.ps1 "git diff origin/master...origin/develop" "" -assertExactMatch -assertPass

RUN git log --all --graph --decorate

# Two releases

FROM build
RUN echo 'two release workflow'

RUN git checkout develop
RUN echo hi >> README.md
RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Branch release-100" -assertExactMatch -assertPass

RUN git checkout develop
RUN echo hi >> README.md
RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 101
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Branch release-100 Branch release-101" -assertExactMatch -assertPass

RUN pwsh /app/release.ps1 -mark_released -create_tag -version 100
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Branch release-101 Tag v100" -assertExactMatch -assertPass
RUN pwsh /app/release.ps1 -mark_released -create_tag -version 101

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Tag v101 Tag v100" -assertExactMatch -assertPass

RUN git log --all --graph --decorate

# Hotfix releases

FROM build
RUN echo 'hotfix workflow'

RUN git checkout develop
RUN echo hi >> README.md
RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100

RUN git checkout release-100
RUN echo hi >> README.md
RUN git commit -a -m "Hotfix readme update"
RUN git push origin release-100

RUN pwsh /app/release.ps1 -create_release -version 101

RUN pwsh /app/release.ps1 -create_hotfix_release -version 100.1 -hotfix_base_branch release-100

RUN git checkout release-100-1
RUN echo hi >> README.md
RUN git commit -a -m "Hotfix readme update"
RUN git push origin release-100-1

RUN pwsh /app/release.ps1 -mark_released -create_tag -version 100
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -mark_released -create_tag -version 100.1" "Backmerge required, please open: /git-upstream/.git/compare/master?expand=1&title=Backmerge+from+master+to+develop&body=Backmerge Backmerge required for release-101, please open: /git-upstream/.git/compare/release-101...master?expand=1&title=Backmerge+from+master+to+release-101&body=Backmerge" -assertPass -assertPartialMatch
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -backmerge" "Backmerge required, please open: /git-upstream/.git/compare/master?expand=1&title=Backmerge+from+master+to+develop&body=Backmerge Backmerge required for release-101, please open: /git-upstream/.git/compare/release-101...master?expand=1&title=Backmerge+from+master+to+release-101&body=Backmerge" -assertPass -assertPartialMatch

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -mark_released -version 101" "master contains commits not merged back into release-101. Please fix that before proceeding. /git-upstream/.git/compare/master?expand=1&title=Backmerge+from+master+to+develop&body=Backmerge" -assertPartialMatch -assertFail

RUN git checkout release-101
RUN git merge origin/master -m "Backmerge"
RUN git push origin release-101

RUN pwsh /app/release.ps1 -mark_released -create_tag -version 101

RUN git checkout develop
RUN git merge origin/master -m "Backmerge"
RUN git push origin develop

RUN git log --all --graph --decorate

# List releases

FROM build
RUN echo 'list releases'

RUN pwsh /app/release.ps1 -create_release -create_tag -version 100
RUN pwsh /app/release.ps1 -create_release -create_tag -version 100.1
RUN pwsh /app/release.ps1 -create_release -create_tag -version 101

RUN git checkout -b release-100-2-somedata
RUN git push origin release-100-2-somedata

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Branch release-100 Branch release-100-1 Branch release-101" -assertExactMatch -assertPass

# Github URL mapping

FROM build
RUN echo 'github url testing'

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git" -assertExactMatch -assertPass
RUN git remote rm origin
RUN git remote add origin https://github.com/dustinsoftware/gitflow-scratch.git
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "https://github.com/dustinsoftware/gitflow-scratch" -assertPartialMatch

RUN git remote rm origin
RUN git remote add origin git@github.com:dustinsoftware/gitflow-scratch.git
RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "https://github.com/dustinsoftware/gitflow-scratch" -assertPartialMatch

# Major.minor.patch release

FROM build
RUN echo 'typical workflow'

RUN echo hi >> README.md

RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100
RUN pwsh /app/release.ps1 -create_release -version 100.1
RUN pwsh /app/release.ps1 -create_release -version 100.1.1

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -create_release -version 100.1.1.1" -assertFail

RUN pwsh /app/assertOutput.ps1 "pwsh /app/release.ps1 -list_releases" "/git-upstream/.git Branch release-100 Branch release-100-1 Branch release-100-1-1" -assertExactMatch -assertPass
