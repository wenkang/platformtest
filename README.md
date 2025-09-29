# Thermal compensation analysis toolkit

This repository aggregates laser displacement measurements from several
`platformtest_*.csv` files and now includes a MATLAB helper function for
building temperature-compensation models that respect the mixed-material
stack in the measurement path.

## MATLAB workflow

1. Start MATLAB in this folder.
2. Run the analysis function:

   ```matlab
   results = temperature_compensation_analysis('.', ...
       'ReferenceTemperature', 31.0, ...
       'SensorDriftOrder', 3, ...
       'MaterialStack', struct(
           'aluminumLength', 0.052 ... % customise support length (metres)
       ));
   ```

   The helper will:

   - load every `platformtest_*.csv` file;
   - compute the expected mechanical expansion from steel (per `test_level`),
     zirconia and aluminium sections using configurable coefficients of thermal
     expansion;
   - fit per-channel linear models that separate level offsets, mechanical
     expansion and higher-order sensor drift terms; and
   - print RMS/peak residuals so you can confirm whether the 0.5 µm target is
     met. Setting the `SensorDriftOrder` to ≥2 allows the optical sensor’s
     thermal drift to deviate from pure linearity while staying monotonic over
     the captured temperature range.

3. Inspect `results.summary` for error statistics and, if you call the function
   without an output argument, review the automatically generated diagnostic
   plots to look for systematic residual structure.

## Modelling considerations

- The `MaterialStack` struct lets you fine-tune path lengths (in metres) for
  each material. By default the steel thickness is derived directly from the
  `test_level` column (interpreted in millimetres), the zirconia clamp length is
  fixed at 22 mm, and aluminium defaults to 0 so you can decide how much of the
  support frame is co-linear with the laser axis.
- Thermal expansion coefficients can be overridden via the
  `ExpansionCoefficients` option, making it straightforward to test scenarios
  such as swapping in different alloys or ceramics.
- Residuals well above the sub-micron requirement typically indicate either
  (i) incorrect assumptions about material lengths/CTEs, (ii) unmodelled sensor
  drift (increase `SensorDriftOrder`), or (iii) imperfect thermal equilibrium
  during acquisition. Use the residual plots to diagnose non-linearity or
  hysteresis.

