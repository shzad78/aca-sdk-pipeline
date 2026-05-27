# Axis Communications — Learning Session
**Date:** 2026-05-26
**Topics:** ACAP Pipeline, sdk-seed.groovy, Sprint 107, Bitbake Commands

---

## Table of Contents
1. [Whiteboard Diagram — Detailed Explanation](#1-whiteboard-diagram--detailed-explanation)
2. [Full Pipeline Flow](#2-full-pipeline-flow)
3. [Node/React Comparison](#3-nodereact-comparison)
4. [Pipeline Code Skeleton](#4-pipeline-code-skeleton)
5. [sdk-seed.groovy Explained](#5-sdk-seedgroovy-explained)
6. [Why Standalone Jobs Exist](#6-why-standalone-jobs-exist)
7. [File Types in the Jenkins Repo](#7-file-types-in-the-jenkins-repo)
8. [Concrete Build Example — ARTPEC-9 aarch64](#8-concrete-build-example--artpec-9-aarch64)
9. [Sprint 107 Board](#9-sprint-107-board)
10. [All Commands — Step 1 Bitbake Builds SDK](#10-all-commands--step-1-bitbake-builds-sdk)
11. [Windows Commands](#11-windows-commands)

---

## 1. Whiteboard Diagram — Detailed Explanation

### The Version Tree (left side)

```
10  ──┐
11  ──┤  Axis OS major versions (LTS tracks)
12  ──┤
      └── Preview 13.0  ← current focus (ARTPEC-9)
```

| Whiteboard Label | Internal Branch         | Chip Family                        |
|------------------|-------------------------|------------------------------------|
| OS 10            | rel/fw-10.12/maint      | ARTPEC-6/7                         |
| OS 11            | rel/fw-11.11/maint      | ARTPEC-6/7/8, Ambarella S5         |
| OS 12            | rel/fw-12.11/maint      | ARTPEC-6/7/8/9                     |
| Preview 13.0     | master                  | ARTPEC-9 (new)                     |

### The Central Circle — "Axis OS"

The circle is not just the OS — it represents the **entire bitbake/Yocto build system**.
When fed a version branch it produces:

1. **A firmware image** — flashed onto the physical camera
2. **A Bitbake SDK** — self-extracting `.sh` installer with toolchain + API headers

SDK installer lands in Artifactory:
```
firmware-releases-cfp/release/acapsdk/sdk/{major.minor}/
  └── {sdk_version}/
        ├── cortexa9hf-neon/    ← armv7hf
        │     └── ACAPSDK_{version}_cortexa9hf-neon_setup.sh
        └── cortexa53-crypto/   ← aarch64
              └── ACAPSDK_{version}_cortexa53-crypto_setup.sh
```

### The Two Arrows from Bitbake SDK

```
Bitbake SDK (.sh installer)
    │
    ├──► API       → headers, shared libraries (.so), pkg-config files
    │               (what the ACAP app links against at compile time)
    │
    └──► Toolchain → cross-compiler (gcc/g++ for arm/aarch64),
                     sysroot, linker
                     (what does the actual compilation)
```

**Node/React analogy:**
- API = `node_modules/` (what your app imports at build time)
- Toolchain = the Node.js binary + npm itself (what runs the build)

### The Output — Acap-Native SDK

The `acap-native-sdk` is a **Docker image** published to Docker Hub:
```
axisecp/acap-native-sdk:master-aarch64-ubuntu24.04
axisecp/acap-native-sdk:master-armv7hf-ubuntu24.04
```

**Internal vs Public:**
- **Internal** → `docker-sandbox.se.axis.com/axisecp/acap-native-sdk` (staging)
- **Public** → `docker-prod.se.axis.com/axisecp` → Docker Hub `axisecp`

### The Two Architectures

| Label   | Bitbake pkg arch  | Maps to chip family                |
|---------|-------------------|------------------------------------|
| AARCH64 | cortexa53-crypto  | ARTPEC-8, ARTPEC-9, Ambarella CV25 |
| ARMV7HF | cortexa9hf-neon   | ARTPEC-7 and earlier               |

---

## 2. Full Pipeline Flow

```
INPUT
  AXIS_OS_VERSION = "Preview-13.0"
  SDK_VERSION     = "13.0.0_rc1"
  CONTAINER_TAG   = "preview-13"
  UBUNTU_VERSION  = "24.04"
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ STAGE 1: Extract Bitbake SDK from Artifactory        │
│  job: sdk-extraction                                 │
│  ├── downloads ACAPSDK_*.sh from Artifactory         │
│  ├── runs extract_apifiles.sh     → {arch}.tar       │
│  ├── runs extract_sdkartifacts.sh → sdk_{arch}.tar   │
│  └── re-uploads both tarballs to Artifactory         │
└──────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ STAGE 2: Build API + Toolchain container images      │
│  job: api3-builder      (armv7hf + aarch64)          │
│  job: toolchain-builder (armv7hf + aarch64)          │
│  docker build → push to docker-sandbox               │
└──────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ STAGE 3: Build acap-native-sdk image                 │
│  job: acap-native-sdk-build-groovy (per arch)        │
│  Clones acap-native-sdk GitHub repo                  │
│  docker build using Dockerfile.{arch}                │
│  docker push → docker-sandbox                        │
└──────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ STAGE 4: Publish — Internal + Public                 │
│  job: Generator                                      │
│  docker tag sandbox → docker-prod (internal)         │
│  docker tag sandbox → axisecp Docker Hub (public)    │
└──────────────────────────────────────────────────────┘

OUTPUT
  axisecp/acap-native-sdk:preview-13-aarch64-ubuntu24.04
  axisecp/acap-native-sdk:preview-13-armv7hf-ubuntu24.04
```

---

## 3. Node/React Comparison

### Conceptual Mapping

| Axis ACAP concept            | Node/React equivalent                      |
|------------------------------|--------------------------------------------|
| Axis OS version branch       | Node.js LTS version (18, 20, 22)           |
| Bitbake SDK `.sh` installer  | Node.js release tarball / nvm install      |
| API extraction (headers)     | `npm install` — your `node_modules/`       |
| Toolchain extraction         | The Node binary + npm itself               |
| `acap-native-sdk` image      | `node:20-alpine` base image on Docker Hub  |
| `.eap` output file           | `build/` static files or `.tgz` npm pkg   |
| AARCH64 / ARMV7HF            | linux/amd64, linux/arm64 multi-arch build  |
| docker-sandbox registry      | Private ECR staging / internal Artifactory |
| docker-prod / Docker Hub     | npmjs.com / Docker Hub public              |

### Side-by-Side Pipeline

**React/Node CI:**
```yaml
jobs:
  build:
    strategy:
      matrix:
        platform: [linux/amd64, linux/arm64]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run build
      - run: docker build -t myapp .
      - run: docker push staging/myapp
      - run: docker push public/myapp
```

**ACAP Jenkins equivalent:**
```groovy
stage('Extract Bitbake SDK') {           // ← npm ci
    parallel extractionTasks
}
stage('Build API + Toolchain images') {  // ← setup-node
    parallel buildContainerTasks
}
stage('Build acap-native-sdk image') {   // ← docker build
    parallel buildSdkTasks
}
stage('Publish Internal + Public') {     // ← docker push
    parallel publishTasks
}
```

### Key Structural Differences

**1. Jobs chain instead of stages**
```
React:   Single job → [stage1 → stage2 → stage3 → stage4]

ACAP:    Orchestrator
              ├── build job: sdk-extraction
              ├── build job: api3-builder
              ├── build job: acap-native-sdk-build
              └── build job: Generator
```

**2. The SDK container IS the compiler**
```bash
# React developer:
npm run build

# ACAP developer:
docker run --rm \
  -v $PWD:/opt/app \
  axisecp/acap-native-sdk:13.0.0-aarch64-ubuntu24.04
# → produces hello-world.eap
```

**3. Real hardware in tests**
```
React:   Jest runs in a virtual Node process
ACAP:    withAxisDevice reserves a physical Axis camera,
         flashes firmware, installs .eap, runs pytest on real device
```

**4. Multiple long-lived branches**
```
React:     main → production
           develop → staging

ACAP:      master          → SDK 13 nightly (ARTPEC-9)
           rel/fw-12.11    → SDK 12 LTS nightly
           rel/fw-11.11    → SDK 11 LTS nightly
           rel/fw-10.12    → SDK 10 LTS nightly
```

**5. Seed jobs — no React equivalent**
```
React:    Write Jenkinsfile → Jenkins runs it directly

ACAP:     Write sdk-seed.groovy
               ↓ Run the seed job
          Jenkins creates child jobs:
               - Base job
               - Q6075-AcapSDK (ARTPEC-7)
               - Q1656-AcapSDK (ARTPEC-8)
               - Q1728-AcapSDK (ARTPEC-9)
               ↓ Run those child jobs
          Actual build + test happens
```

---

## 4. Pipeline Code Skeleton

```groovy
/* acap-native-sdk-image-pipeline.groovy
 * Place at: Pipelines/ECP/NewReleaseFlow/acap-native-sdk-image-pipeline.groovy */

def archs = [
    ["armv7hf",  "cortexa9hf-neon",  ""],
    ["aarch64",  "cortexa53-crypto",  ""]
]

def docker_sandbox = "docker-sandbox.se.axis.com/axisecp"
def docker_prod    = "docker-prod.se.axis.com/axisecp"

def axisOsVersionMap = [
    "OS-10"        : [branch: "rel/fw-10.12/maint", distro13: false],
    "OS-11"        : [branch: "rel/fw-11.11/maint", distro13: false],
    "OS-12"        : [branch: "rel/fw-12.11/maint", distro13: false],
    "Preview-13.0" : [branch: "master",              distro13: true ],
]

def selectedVersion = axisOsVersionMap[params.AXIS_OS_VERSION]
def sdkBranch       = selectedVersion.branch
def distro13        = selectedVersion.distro13

def assembleArtifactoryPath(sdk_version, pkg_arch, use_distro13) {
    def base_path    = "firmware-releases-cfp/release/acapsdk/sdk"
    def sdk_dir      = sdk_version.find(/\d+\.\d+/)
    def setup_script = "ACAPSDK_${sdk_version}_${pkg_arch}_setup.sh"
    return "${base_path}/${sdk_dir}/${sdk_version}/${pkg_arch}/${setup_script}"
}

archs.each { arch ->
    arch[2] = assembleArtifactoryPath(params.SDK_VERSION, arch[1], distro13)
}

/* STAGE 1 — Extract SDK */
def extractionTasks = [:]
archs.each { arch ->
    def niceName = arch[0]
    def pkgArch  = arch[1]
    def artiPath = arch[2]
    extractionTasks["Extract SDK for ${niceName}"] = {
        build job: 'sdk-extraction',
            parameters: [
                string(name: 'SDK_VERSION',          value: params.SDK_VERSION),
                string(name: 'SDK_PATH_ARTIFACTORY', value: artiPath),
                string(name: 'SDK_PKG_ARCH',         value: pkgArch),
                string(name: 'GIT',                  value: params.CONTAINER_IMAGES_GIT)
            ]
    }
}

/* STAGE 2 — Build API + Toolchain */
def buildContainerTasks = [:]
archs.each { arch ->
    def niceName = arch[0]
    def pkgArch  = arch[1]
    buildContainerTasks["Build acap-api for ${niceName}"] = {
        build job: 'api3-builder',
            parameters: [
                string(name: 'SDK_VERSION',              value: params.SDK_VERSION),
                string(name: 'ARCH',                     value: niceName),
                string(name: 'PKG_ARCH',                 value: pkgArch),
                string(name: 'GIT',                      value: params.CONTAINER_IMAGES_GIT),
                string(name: 'CONTAINER_UBUNTU_VERSION', value: params.CONTAINER_UBUNTU_VERSION),
                string(name: 'CONTAINER_TAG_VERSION',    value: params.CONTAINER_TAG_VERSION)
            ]
    }
    buildContainerTasks["Build acap-toolchain for ${niceName}"] = {
        build job: 'toolchain-builder',
            parameters: [
                string(name: 'SDK_VERSION',                      value: params.SDK_VERSION),
                string(name: 'ARCH',                             value: niceName),
                string(name: 'PKG_ARCH',                         value: pkgArch),
                string(name: 'GIT',                              value: params.CONTAINER_IMAGES_GIT),
                string(name: 'CONTAINER_UBUNTU_VERSION',         value: params.CONTAINER_UBUNTU_VERSION),
                string(name: 'CONTAINER_TAG_VERSION',            value: params.CONTAINER_TAG_VERSION),
                string(name: 'AXIS_ACAP_MANIFEST_TOOLS_VERSION', value: params.AXIS_ACAP_MANIFEST_TOOLS_VERSION)
            ]
    }
}

/* STAGE 3 — Build acap-native-sdk */
def buildSdkTasks = [:]
archs.each { arch ->
    def niceName = arch[0]
    buildSdkTasks["Build acap-native-sdk for ${niceName}"] = {
        build job: 'acap-native-sdk-build-groovy',
            parameters: [
                string(name: 'ARCH',                     value: niceName),
                string(name: 'GIT',                      value: params.CONTAINER_IMAGES_GIT),
                string(name: 'ACAP_NATIVE_SDK_GIT',      value: params.ACAP_NATIVE_SDK_GIT),
                string(name: 'USE_STAGING_ACAP_NATIVE_SDK_GIT_REPO', value: "false"),
                string(name: 'CONTAINER_UBUNTU_VERSION', value: params.CONTAINER_UBUNTU_VERSION),
                string(name: 'CONTAINER_TAG_VERSION',    value: params.CONTAINER_TAG_VERSION),
                string(name: 'AXIS_OS_VERSION_REF',      value: sdkBranch)
            ]
    }
}

/* STAGE 4 — Publish */
def publishTasks = [:]
archs.each { arch ->
    def niceName = arch[0]
    publishTasks["Publish acap-native-sdk for ${niceName}"] = {
        build job: 'Teams/ACAP_Framework/ECP/Release/Generator',
            parameters: [
                string(name: 'ARCH',                     value: niceName),
                string(name: 'IMAGE_REPO',               value: "acap-native-sdk"),
                string(name: 'CONTAINER_UBUNTU_VERSION', value: params.CONTAINER_UBUNTU_VERSION),
                string(name: 'CONTAINER_TAG_VERSION',    value: params.CONTAINER_TAG_VERSION)
            ]
    }
}

stage('Extract Bitbake SDK from Artifactory') { parallel extractionTasks    }
stage('Build API and Toolchain images')        { parallel buildContainerTasks }
stage('Build acap-native-sdk image')           { parallel buildSdkTasks       }
stage('Publish to Internal and Public')        { parallel publishTasks         }
```

### Jenkins Parameters Block

```groovy
parameters {
    choice(name: 'AXIS_OS_VERSION',
           choices: ['Preview-13.0', 'OS-12', 'OS-11', 'OS-10'],
           description: 'Axis OS major version')
    string(name: 'SDK_VERSION',         defaultValue: '13.0.0_rc1')
    string(name: 'CONTAINER_TAG_VERSION', defaultValue: 'preview-13')
    string(name: 'CONTAINER_UBUNTU_VERSION', defaultValue: '24.04')
    string(name: 'AXIS_ACAP_MANIFEST_TOOLS_VERSION', defaultValue: '')
    string(name: 'CONTAINER_IMAGES_GIT', defaultValue: '')
    string(name: 'ACAP_NATIVE_SDK_GIT',  defaultValue: '')
}
```

---

## 5. sdk-seed.groovy Explained

### File Structure

```
library 'bff'
bffSeed {
    // 1. Read input parameters
    // 2. Compute tags and versions
    // 3. Set shared BFF settings

    if (job_type == "team-test") {
        // 4a. Configure team integration test jobs
    }
    if (job_type == "nightly-sdk-release") {
        // 4b. Configure nightly SDK release jobs
    }
}
```

### Key Concepts

| Line | What it does |
|---|---|
| `library 'bff'` | Loads Axis internal Jenkins shared library |
| `bffSeed { }` | Describes generated jobs — not a running pipeline |
| `this.params.X` | Reads parameters of the seed job itself |
| `manifest_branch` | Which branch of `dists/manifests` drives workspace sync |
| `container_tag` | Docker image tag (slashes replaced with dashes) |
| `parameter name:` | Adds visible parameter to generated job |
| `expose(...).asParameter()` | Promotes BFF backend setting to UI parameter |
| `product name: 'Q1656'` | Creates sub-job for that physical camera |
| `VARIANTS = 'AcapSDK'` | Names the build variant |
| `customization 'AcapSDK', script` | Injects Groovy into AcapSDK variant |
| `readTrusted('SDK/function-test.groovy')` | Loads file from git repo root |
| `job_type == "team-test"` | Developer integration test configuration |
| `job_type == "nightly-sdk-release"` | Nightly build + publish configuration |
| `OE_DISTRO_13` | Switch for Preview 13.0 / ARTPEC-9 mode |

### Hardware Product Matrix

```
master branch:
  Q6075 (ARTPEC-7) ✓
  Q1656 (ARTPEC-8) ✓
  Q1728 (ARTPEC-9) ✓   ← added, master only
  FA54  (ARTPEC-6) ✗

rel/fw-11.11/maint branch:
  Q6075 (ARTPEC-7) ✓
  Q1656 (ARTPEC-8) ✓
  Q1728 (ARTPEC-9) ✗   ← no ARTPEC-9 for LTS 11
  FA54  (ARTPEC-6) ✓   ← added
  P3719 (Ambarel.) ✓   ← Ambarella S5, LTS 11 only
```

### Complete Generated Flow

```
sdk-seed.groovy (runs once)
        │
        ▼
Generated jobs (run every nightly/team-test):
  ┌─── Base job
  │      └── [start-pipeline.groovy] → triggers new-release-builder
  ├─── Q6075-AcapSDK (ARTPEC-7)
  │      └── [function-test.groovy]
  ├─── Q1656-AcapSDK (ARTPEC-8)
  │      └── [function-test.groovy]
  └─── Q1728-AcapSDK (ARTPEC-9) ← master only
         └── [function-test.groovy]
```

---

## 6. Why Standalone Jobs Exist

### 4 Reasons

**Reason 1 — Seeds generate families, not single jobs**
Seeds make sense when the same structure repeats across multiple products/branches.
`new-release-builder.groovy` only ever exists as one job — no need for a seed.

**Reason 2 — Standalone pipelines are called BY seed-generated jobs**
```
sdk-seed → Base job → start-pipeline.groovy → new-release-builder ← standalone
```
`new-release-builder` is a downstream worker called programmatically at runtime.

**Reason 3 — Not every job needs BFF**
Seeds use `bffSeed {}` which requires BFF, FWRT, Reactor, sstate cache.
`sdk-extraction.groovy` is just Docker + curl — forcing it into BFF adds complexity for zero benefit.

**Reason 4 — Some scripts are admin tools, not CI jobs**
`create_sdk_branches.sh` runs manually twice a year to create LTS release branches.
It is not a pipeline at all.

### The Right Mental Model

| Tool | Use when | Example |
|---|---|---|
| Seed file | Same job × N products/branches | sdk-seed.groovy |
| Standalone pipeline | Single specific job, called programmatically | new-release-builder |
| Shell script | Logic in bash, sourced inside pipelines or run manually | create_sdk_branches.sh |

---

## 7. File Types in the Jenkins Repo

### Type 1 — Seed files (`*-seed.groovy`)
```
SDK/sdk-seed.groovy
SDK/LTS-11.11-SDK-4.15/sdk-seed.groovy
Firmware/firmware-seed.groovy
Firmware/lts-1111-seed.groovy
SDK_release/sdk-release-fwrt-seed.groovy
Acaps/Test-Github-Acap-Examples/function-test-seed.groovy
```

### Type 2 — Customization/hook scripts
```
SDK/function-test.groovy         ← injected into AcapSDK variant jobs
SDK/start-pipeline.groovy        ← injected into Base job after nightly build
SDK/cv-solution-pipeline.groovy
```

### Type 3 — Standalone pipelines
```
Acaps/Build-Github-Acap-Examples/build-github-acap-examples.groovy
Pipelines/ECP/NewReleaseFlow/new-release-builder.groovy
Pipelines/ECP/NewReleaseFlow/acap-native-sdk-builder.groovy
Pipelines/ECP/NewReleaseFlow/sdk-extraction.groovy
SDK_release/sdk-release-pipeline.groovy
```

### Type 4 — Shell scripts
```
libs/log-utils.sh
libs/acap-build-acap-examples/test-utils.sh
Acaps/Build-Github-Acap-Examples/test-cases.sh
SDK_release/create-copyleft.sh
Scripts/SDK/create_sdk_branches.sh
```

---

## 8. Concrete Build Example — ARTPEC-9 aarch64

### Step 1 — Bitbake produces the SDK installer

```bash
# bitbake recipe that produces the SDK .sh
bitbake acap-native-sdk-populate-sdk

# Output:
build/tmp/deploy/sdk/ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh
```

Uploaded to Artifactory at:
```
firmware-releases-cfp/release/acapsdk/sdk/13.0/13.0.0_rc1/
  cortexa53-crypto/ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh
```

### Step 2 — sdk-extraction.groovy downloads and extracts

```bash
# Download installer
curl -u${ART_USER}:${ART_API_KEY} \
     -O "${ART_URL}/firmware-releases-cfp/release/acapsdk/sdk/13.0/13.0.0_rc1/cortexa53-crypto/ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh"

# Run it — extracts to ./bitbake_sdk/
chmod +x ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh
./ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh -d ./bitbake_sdk -y

# Run extraction scripts
./extract_apifiles.sh cortexa53-crypto.txt        # → cortexa53-crypto.tar
./extract_sdkartifacts.sh sdk_cortexa53-crypto.txt # → sdk_cortexa53-crypto.tar

# Re-upload tarballs
curl -u${ART_USER}:${ART_API_KEY} -T cortexa53-crypto.tar \
     "${ART_URL}/acap-sdk/ecp/preview-13/cortexa53-crypto.tar"
curl -u${ART_USER}:${ART_API_KEY} -T sdk_cortexa53-crypto.tar \
     "${ART_URL}/acap-sdk/ecp/preview-13/sdk_cortexa53-crypto.tar"
```

### Step 3 — acap-native-sdk-builder.groovy builds the Docker image

```bash
git clone https://github.com/AxisCommunications/acap-native-sdk.git
git clone ssh://gittools.se.axis.com:29418/teams/ecp/container-images
cd container-images/builder-acap-native-sdk

./build.sh \
    --arch aarch64 \
    --sdk preview-13 \
    --ubuntu 24.04 \
    --dockerfile ../../acap-native-sdk/Dockerfile.aarch64 \
    --repo docker-sandbox.se.axis.com/axisecp \
    --tag docker-sandbox.se.axis.com/axisecp/acap-native-sdk:preview-13-aarch64-ubuntu24.04 \
    --axis-os-version-ref "master"

docker push docker-sandbox.se.axis.com/axisecp/acap-native-sdk:preview-13-aarch64-ubuntu24.04
```

### Step 4 — Developer uses the final image

```c
/* hello_world.c */
#include <syslog.h>
int main(void) {
    openlog("hello_world", LOG_PID | LOG_CONS, LOG_USER);
    syslog(LOG_INFO, "Hello from ARTPEC-9!");
    closelog();
    return 0;
}
```

```bash
# Developer compiles using the SDK image
docker run --rm \
    -v $PWD:/opt/app \
    axisecp/acap-native-sdk:preview-13-aarch64-ubuntu24.04 \
    make
# → produces hello_world.eap

# Install onto camera
curl -u root:pass \
     "http://192.168.1.100/axis-cgi/applications/upload.cgi" \
     -F packfil=@hello_world.eap
```

---

## 9. Sprint 107 Board

**Sprint:** Sprint 107
**Goal:** Review-first mindset 1.15.2 release Ready for 12.11 release (w25)
**Time remaining:** 14 days

### All Tickets

| Ticket | Title | Column | Tag |
|---|---|---|---|
| ECODEVT-2106 | Release 1.15.2 | TO DO | Service release 1.1 |
| ECODEVT-1887 | Verify acap-build scripts | TO DO | Work before SDK |
| ECODEVT-1974 | Add custom schemas for internal ACAP | IN PROGRESS | SDK 13.0 preview |
| ECODEVT-2055 | Add tests for vendorUrl | IN PROGRESS | SDK & manifest m... |
| ECODEVT-1603 | Remove pkgconf stuff from SDK | REVIEW | Work before SDK |
| ECODEVT-1984 | Support FT Team creating/reviewing example | REVIEW | Support PTZ in del... |
| ECODEVT-1883 | Document manifest schema v2 | INTEGRATION | Service release 1.1 |
| ECODEVT-1600 | Update acap-build and eap-install.sh for SDK 13 | INTEGRATION | SDK 13.0 preview |

### Column Meanings

```
TO DO       → Accepted into sprint, nobody working yet
IN PROGRESS → Actively coding/investigating
REVIEW      → Code done, waiting for Gerrit review approval
INTEGRATION → Approved in Gerrit, running in CI
DONE        → Merged, verified, closed
```

### Sprint Management Approach

```
Daily morning (5 min):
  1. Check REVIEW column first — unblock a teammate
  2. Check your IN PROGRESS — what is next concrete action?
  3. If blocked → who do you message?

Standup (1 min):
  Yesterday: [what you moved forward]
  Today:     [next concrete step — be specific]
  Blocker:   [name it clearly]

Before end of day:
  Push your branch even if incomplete
  Add comment to Jira ticket
```

### Vertical Slice Example (ECODEVT-1974)

```
Day 1-2:  Read ticket. Find linked repo. Understand "custom schema."
          Look at ECODEVT-1600 (INTEGRATION) — yours builds on it.

Day 3-4:  git checkout -b user/shahzad/custom-schemas-internal-acap
          Make first small change. Push. Point staging Jenkins at branch.

Day 5-7:  git push origin HEAD:refs/for/master
          Move ticket to REVIEW in Jira.

Day 8-10: Address review comments. Re-push.

Day 11-14: Monitor CI. Fix breaks. Move to DONE when merged.
```

---

## 10. All Commands — Step 1 Bitbake Builds SDK

### Layer 1 — FWRT Seed (from sdk-release-fwrt-seed.groovy)

```groovy
@Library(['bff']) _
bffSeed {
    VARIANTS = 'Fwrt'

    product(name: 'cortexa53-crypto', softwareName: 'acapsdk') {
        oeExecuteFwrt['--architecture'] = 'cortexa53-crypto'  // aarch64
    }
    product(name: 'cortexa9hf-neon', softwareName: 'acapsdk') {
        oeExecuteFwrt['--architecture'] = 'cortexa9hf-neon'   // armv7hf
    }

    oeExecuteFwrt['releaseType']         = 'sdk'
    oeExecuteFwrt['--release-producer']  = 'sdk'
    oeExecuteFwrt['--release-track']     = 'active'
    oeExecuteFwrt['--manifest-file']     = 'axisos/axisos.xml'
    oeExecuteFwrt['--build-stage']       = stage
    oeExecuteFwrt['--version']           = version
    oeExecuteFwrt['--sequence-number']   = seq_no
    oeExecuteFwrt['--manifest-branch']   = manifest_branch

    if (this.params.OE_DISTRO_13) {
        oeExecuteFwrt['--distro'] = 'axisos-13-preview'
    }
}
```

### Layer 2 — repo tool workspace sync

```bash
repo init \
    -u ssh://svcj@gittools.se.axis.com:29418/dists/manifests \
    -b master \
    -m cvp.xml

# Optional: local manifest patch (OE_LOCAL_MANIFEST)
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/local.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <extend-project name="layers/meta-axis"
                  revision="refs/changes/16/909816/4"/>
</manifest>
EOF

repo sync --jobs=8
```

### Layer 3 — Yocto build commands

```bash
# Source OE environment
source oe-init-build-env build

# Append OE_LOCAL_OVERRIDES to local.conf
echo 'SRCREV:pn-nativesdk-acap-dev-tools = "refs/changes/93/172993/2"' \
     >> build/conf/local.conf

# Build the SDK installer
bitbake acap-native-sdk-populate-sdk

# Check output
ls build/tmp/deploy/sdk/
# ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh
```

### Layer 4 — Upload to Artifactory

```bash
VERSION="13.0.0_rc1"
ARCH="cortexa53-crypto"
MAJOR_MINOR="13.0"
TARGET="firmware-releases-cfp/release/acapsdk/sdk/${MAJOR_MINOR}/${VERSION}/${ARCH}"

curl -u${ART_USER}:${ART_API_KEY} \
     -T build/tmp/deploy/sdk/ACAPSDK_${VERSION}_${ARCH}_setup.sh \
     "https://artifacts.se.axis.com/artifactory/${TARGET}/ACAPSDK_${VERSION}_${ARCH}_setup.sh"
```

---

## 11. Windows Commands

### Check what you already have (PowerShell)

```powershell
wsl --list --verbose   # WSL2 already installed?
docker version         # Docker Desktop installed?
git --version          # Git installed?
winver                 # Windows build version
```

### If WSL2 not installed (PowerShell Admin)

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```

### repo tool in WSL2

```bash
sudo apt-get update && sudo apt-get install -y git python3 curl
mkdir -p ~/.bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod +x ~/.bin/repo
echo 'export PATH="${HOME}/.bin:${PATH}"' >> ~/.bashrc
source ~/.bashrc
repo version
```

### Yocto dependencies in WSL2

```bash
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool file
```

### Pull public Axis SDK image (PowerShell — no WSL2 needed)

```powershell
docker pull axisecp/acap-native-sdk:master-aarch64-ubuntu24.04
docker run --rm -it axisecp/acap-native-sdk:master-aarch64-ubuntu24.04 bash
```

```bash
# Inside container — explore what the pipeline produces
aarch64-poky-linux-gcc --version
ls /usr/local/include/
```

### Artifactory upload practice (PowerShell)

```powershell
$ART_URL  = "https://trialua6vjw.jfrog.io/artifactory"
$ART_USER = "your-username"
$ART_KEY  = "your-api-key"

"fake sdk content" | Out-File "ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh"

curl.exe -u "${ART_USER}:${ART_KEY}" `
         -T "ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh" `
         "${ART_URL}/libs-release-local/acapsdk/sdk/13.0/ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh"

$response = curl.exe -u "${ART_USER}:${ART_KEY}" `
                     -w "%{http_code}" `
                     -O "downloaded.sh" `
                     "${ART_URL}/libs-release-local/acapsdk/sdk/13.0/ACAPSDK_13.0.0_rc1_cortexa53-crypto_setup.sh"
Write-Host "HTTP: $response"
```

### Do you need WSL2?

| Task | WSL2 needed | Alternative |
|---|---|---|
| repo tool + manifest XML | YES | Use Docker |
| bitbake commands | YES | Use Docker |
| Docker SDK exploration | NO | PowerShell |
| Artifactory curl | NO | PowerShell curl.exe |
| Git / Gerrit | NO | Git for Windows |

**Quickest path — no installation needed:**
```powershell
docker pull axisecp/acap-native-sdk:master-aarch64-ubuntu24.04
docker run --rm -it axisecp/acap-native-sdk:master-aarch64-ubuntu24.04 bash
```

---

## Glossary

| Term | Meaning |
|---|---|
| ACAP | Axis Camera Application Platform |
| Bitbake SDK | Cross-compilation toolchain from Yocto/bitbake |
| ARTPEC-9 | Latest Axis camera SoC, aarch64 only |
| AARCH64 | 64-bit ARM (ARTPEC-8/9, Ambarella CV25) |
| ARMV7HF | 32-bit ARM hard-float (ARTPEC-7 and earlier) |
| .eap | ACAP package file (equivalent to .apk or .deb) |
| docker-sandbox | Internal staging Docker registry |
| docker-prod | Internal production, also retagged to Docker Hub |
| Artifactory | JFrog binary repo at artifacts.se.axis.com |
| Gerrit | Code review + Git hosting at gittools.se.axis.com |
| BFF | Axis internal Jenkins shared library |
| Seed job | Jenkins job that generates other Jenkins jobs |
| Generator | Jenkins job that promotes images sandbox → prod |
| LFP_FT | Physical device pool of Axis cameras for tests |
| sstate-cache | Yocto shared build cache on NFS |
| repo tool | Google multi-repo workspace sync tool |
| FWRT | Firmware Release Tool — Axis internal bitbake wrapper |
| OE_LOCAL_OVERRIDES | Pin one recipe to a Gerrit change in local.conf |
| OE_LOCAL_MANIFEST | Patch the repo manifest to add/override repos |
