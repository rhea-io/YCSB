/**
 * Copyright (c) 2026 YCSB contributors. All rights reserved.
 * <p>
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 * <p>
 * http://www.apache.org/licenses/LICENSE-2.0
 */

package site.ycsb;

import io.rhea.evalsync.ExperimentWorker;

import java.util.Properties;

/**
 * Optional evalsync coordination for Rhea-managed YCSB runs.
 */
final class EvalSyncCoordinator implements AutoCloseable {
  static final String ENABLE_PROPERTY = "evalsync";
  static final String LOAD_BEFORE_RUN_PROPERTY = "evalsync.load_before_run";
  static final String LOAD_OUTPUT_FILE_PROPERTY = "evalsync.load_output_file";
  static final String LOAD_OUTPUT_FILE_PROPERTY_DEFAULT = "ycsb_load.log";

  private final ExperimentWorker worker;
  private boolean measurementStarted;
  private boolean measurementEnded;
  private boolean done;
  private boolean closed;

  private EvalSyncCoordinator(ExperimentWorker worker) {
    this.worker = worker;
  }

  static EvalSyncCoordinator fromProperties(Properties props) {
    if (!Boolean.valueOf(props.getProperty(ENABLE_PROPERTY, "false"))) {
      return disabled();
    }
    return new EvalSyncCoordinator(ExperimentWorker.fromEnvironment());
  }

  static EvalSyncCoordinator disabled() {
    return new EvalSyncCoordinator(null);
  }

  boolean isEnabled() {
    return worker != null;
  }

  void readyAndWaitForStart() {
    if (!isEnabled()) {
      return;
    }
    if (!worker.ready()) {
      throw new IllegalStateException("evalsync READY transition failed");
    }
    if (!worker.waitForStart()) {
      throw new IllegalStateException("evalsync did not receive BEGIN");
    }
  }

  void measureStart() {
    if (!isEnabled()) {
      return;
    }
    if (!worker.measureStart()) {
      throw new IllegalStateException("evalsync MEASURING transition failed");
    }
    measurementStarted = true;
  }

  void measureEnd() {
    if (!measurementStarted || measurementEnded) {
      return;
    }
    if (!worker.measureEnd()) {
      throw new IllegalStateException("evalsync MEASURE_DONE transition failed");
    }
    measurementEnded = true;
  }

  void end() {
    if (!isEnabled() || done) {
      return;
    }
    if (!worker.end()) {
      throw new IllegalStateException("evalsync DONE transition failed");
    }
    done = true;
  }

  void abort(String message) {
    if (!isEnabled() || done) {
      return;
    }
    worker.abort(message);
    done = true;
  }

  @Override
  public void close() {
    if (!isEnabled() || closed) {
      return;
    }
    worker.close();
    closed = true;
  }
}
