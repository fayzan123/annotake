import AnnotakeApp

MainActor.assumeIsolated {
    AppEntry.main(makeUpdater: { SparkleUpdater() })
}
