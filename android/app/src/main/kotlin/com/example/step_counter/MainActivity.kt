package com.example.step_counter

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.step_counter.StepCounterChannel

class MainActivity : FlutterActivity() {

    private lateinit var stepCounterChannel: StepCounterChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        stepCounterChannel = StepCounterChannel(
            context = this,
            binaryMessenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}