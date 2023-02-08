# Git Branches

## develop
Target branch for development for the next version of Qorus Community Edition.  All commits have to be reviewed pass CI before being merged to `develop` or other target release branches.

## feature/nnnn_xxxx_xxxx
Feature branches are for developing all features. Feature branches must be branched off `develop` and then eventually merged back to `develop` after being reviewed etc. Feature branches should be named after the implemented feature.

## bugfix/nnnn_xxxx_xxxx
Bugfix branches are for fixing bugs. Bug branches must be branched off `develop` and then eventually merged back to `develop` after being reviewed etc. Bug branches should be named after the issue id/number being fixed.

## hotfix/nnnn_xxxx_xxxx
Hotfix branches are for fixing bugs in releases. Hotfix branches must be branched off from the release branch and then eventually merged back to the release branch (and then develop, if necessary) after being reviewed etc. Hotfix branches should be named after the issue id/number being fixed.