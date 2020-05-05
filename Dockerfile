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

# Typical workflow
RUN echo 'typical workflow'
FROM build

RUN echo hi >> README.md

RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100
RUN pwsh /app/release.ps1 -mark_released -version 100

RUN git log --all --graph --decorate

# Two releases

RUN echo 'two release workflow'
FROM build

RUN git checkout develop
RUN echo hi >> README.md
RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 100

RUN git checkout develop
RUN echo hi >> README.md
RUN git commit -a -m "Readme update"
RUN git push origin develop

RUN pwsh /app/release.ps1 -create_release -version 101

RUN pwsh /app/release.ps1 -mark_released -version 100
RUN pwsh /app/release.ps1 -mark_released -version 101

RUN git log --all --graph --decorate

