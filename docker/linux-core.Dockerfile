# Platform-neutral logic tests (DedockCore + pure Edge Dock geometry/state machine) on Linux.
# Swift 6.2 matches Package.swift's swift-tools-version and the macOS CI runner.
FROM swift:6.3-noble
WORKDIR /src
# Source is bind-mounted by docker/compose.yml; the build directory lives in a named volume
# so it never collides with the macOS .build/ in the working tree.
ENV SWIFT_SCRATCH=/build
ENTRYPOINT ["ci/linux-test.sh"]
