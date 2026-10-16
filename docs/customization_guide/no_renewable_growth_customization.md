# No-Renewable-Growth Counterfactual

This procedure describes how to run a ReEDS counterfactual that retains existing renewable capacity and prescribed/exogenous renewable builds, while preventing endogenous growth in wind and solar technologies.

The procedure does not modify the ReEDS GAMS source. It uses the existing regional technology-ban input, which is applied to investment availability (`valinv`) rather than to existing capacity or generation availability.

## Scope and assumptions

This procedure assumes that "no renewable growth" means:

- Retain existing wind, utility-scale PV, and PV+battery capacity.
- Retain prescribed or otherwise exogenous future builds.
- Prevent endogenous investments in active onshore wind, offshore wind, utility-scale PV, and PV+battery technologies.
- Retain distributed/rooftop PV, which is an exogenous input pathway.
- Include CSP only if CSP is enabled in the selected case; CSP is not active in the default case.

If the intended counterfactual also removes prescribed builds, distributed PV, or existing renewable capacity, this procedure is not sufficient. Those are separate input pathways and must be changed explicitly.

## Why use `tech_banned` instead of global technology switches?

ReEDS reads `techs_banned.csv` as the `tech_banned(i,r)` table:

```text
reeds/core/setup/b_inputs.gms
```

The model applies that table while constructing `valinv`, the set of allowed investments. The relevant logic removes investment availability for a banned technology and region, except when a prescription applies:

```gams
valinv(i,v,r,t)$[
    tech_banned(i,r)
    $(not sum{pcat$prescriptivelink(pcat,i),
              noncumulative_prescriptions(pcat,r,t) })
] = no ;
```

This makes `tech_banned` appropriate for an endogenous-investment counterfactual:

- Existing capacity remains available.
- Prescribed builds remain allowed.
- Endogenous investment opportunities are removed.

Do **not** use these as the primary mechanism:

- `GSw_OfsWind=0`: this invokes the global `ban(i)` mechanism and removes offshore wind from model consideration rather than only blocking new investment.
- `GSw_PVB=0`: this disables the coupled PVB technology representation and causes input processing to represent existing `pvb_pv` and `pvb_battery` capacity as standalone UPV and `battery_li` instead. Use `GSw_PVB=1` if existing hybrid PVB assets must remain modeled as PVB.
- Siting switches such as `GSw_SitingUPV=limited`: these change resource availability; they do not disable endogenous investment.

## Procedure

### 1. Identify the active technology set

Use the technology file selected by the case's `techs_suffix` switch:

```text
inputs/techs/techs_{techs_suffix}.csv
```

Do not hard-code the technology list from `techs_default.csv`. A case may use a reduced technology file such as `techs_subsetForTesting.csv`, and the active set may contain fewer resource classes.

From the active technology file, select the technologies belonging to these families:

- Onshore wind: technology names beginning with `wind-ons_`
- Offshore wind: technology names beginning with `wind-ofs_`
- Utility-scale PV: technology names beginning with `upv_`
- PV+battery: technology names beginning with `pvb1_`, `pvb2_`, or `pvb3_`, but only for the PVB types enabled by `GSw_PVB_Types`
- CSP: active CSP technologies only when `GSw_CSP` is nonzero

The resulting list must contain only technologies in the active `i` set. Adding technology names that are absent from the active set can cause GAMS input or compilation errors.

### 2. Create a custom ban YAML

Create a case-specific YAML based on:

```text
inputs/state_policies/techs_banned.yaml
```

Preserve the repository's existing state and county bans, then add the active renewable technologies identified in step 1.

The YAML parser accepts only `st` and `county` scopes. For a nationwide counterfactual, add every state represented in the selected case under each renewable technology. A state-wide ban is expanded to all model regions in that state by `copy_files.py`.

Conceptual structure:

```yaml
wind-ons_1:
  st:
    - AL
    - AZ
    # all states represented by the case
wind-ofs_1:
  st:
    - AL
    - AZ
    # all states represented by the case
upv_1:
  st:
    - AL
    - AZ
    # all states represented by the case
pvb1_1:
  st:
    - AL
    - AZ
    # all states represented by the case
```

Repeat this for every active technology in each family. Do not use a made-up global scope such as `all`; the parser rejects scopes other than `st` and `county`.

The conversion logic is in:

```text
reeds/input_processing/copy_files.py
```

It reads the YAML, creates a table with one row per technology and one column per model region, and writes the GAMS-compatible `techs_banned.csv`.

### 3. Make the custom YAML available to input processing

Use a dedicated git branch for this customization. The branch should contain the custom YAML and the corresponding source `runfiles.csv` change, so the workflow is reproducible and does not require temporary destructive replacement or restoration of shared files.

`runreeds.py` applies `file_replacements` before the generated call script runs `copy_files.py`. However, `inputs_case/techs_banned.csv` does not exist at that point; `copy_files.py` creates it later. Do not use a replacement such as:

```text
inputs_case/techs_banned.csv << custom_techs_banned.csv
```

Also do not replace only the copied case file:

```text
reeds/input_processing/runfiles.csv << C:/absolute/path/to/runfiles_no_renewable_growth.csv
```

The generated call script invokes the copied `copy_files.py`, but passes the repository root as its `reeds_path` argument. `copy_files.py` reads `runfiles.csv` from that original repository path, not from the copied case directory. Replacing the copied `runfiles.csv` therefore has no effect on input processing.

On the customization branch, edit the source file:

```text
reeds/input_processing/runfiles.csv
```

Change only the `techs_banned.csv` row so that its source path points to the custom YAML:

```text
techs_banned.csv,inputs/userinput/techs_banned_no_renewable_growth.yaml,1,ignore,ignore,wide,i,,,0,,,,,,
```

Place the custom YAML at:

```text
inputs/userinput/techs_banned_no_renewable_growth.yaml
```

This works because `copy_files.py` resolves `runfiles.csv` through the original `reeds_path`, and the branch-local source change changes the file it actually reads. `copy_files.py` then converts the custom YAML to `inputs_case/techs_banned.csv` before GAMS reads it.

A custom replacement for `copy_files.py` is only needed if this workflow must support concurrent cases with different ban files from the same checkout. It is not needed when the branch is dedicated to this counterfactual.

### 4. Add a case definition

Add a case column to a user case file such as:

```text
cases_seia.csv
```

Because this customization uses a dedicated git branch, no `file_replacements` entry is required. The branch-local source `runfiles.csv` points input processing to the branch-local custom YAML.

Keep the following switches consistent with the base scenario:

- Keep `GSw_OfsWind=1` if existing or prescribed offshore wind must remain available.
- Keep `GSw_PVB=1` if existing PVB must remain available.
- Keep `GSw_SitingUPV`, `GSw_SitingWindOns`, and `GSw_SitingWindOfs` at the intended base-case values.
- Do not change `techs_suffix` unless the counterfactual intentionally uses a different technology set.
- If `GSw_CSP` is nonzero, include active CSP technologies in the ban YAML.

Example case-file fields for the branch-local counterfactual:

```csv
GSw_OfsWind,,,1
GSw_PVB,,,1
```

Use the existing cases-file column layout; the example above shows only the relevant values.

For `USA_fast_no_re_2026`, `GSw_PVB=1` is required because the counterfactual is intended to retain existing PVB as hybrid PVB. With `GSw_PVB=0`, `writecapdat.py` maps `pvb_pv` to `upv` and `pvb_battery` to `battery_li`, which preserves capacity in an aggregated component sense but does not preserve the coupled PVB representation.

### 5. Run input processing first

Run input processing only so the generated ban table can be inspected before solving the model. Use the active ReEDS environment; do not install packages into the system Python environment.

From the repository root:

```text
conda activate reeds2
python runreeds.py -b no_renewable_growth -c seia -s <case-name>
```

Set the case's `input_processing_only` switch according to the repository's normal input-processing-only workflow, or stop after input processing using the generated case script if that is how the local workflow is configured.

Inspect:

```text
runs/<batch>_<case>/inputs_case/techs_banned.csv
```

Confirm that:

- Every active wind, UPV, PVB, and—if applicable—CSP technology appears as a row.
- Every model region appears as a region column.
- The relevant technologies have a ban value of `1` in every intended region.
- Unrelated technologies retain their original ban values.
- The custom runfiles path was actually used.

### 6. Run the full case

After validating the generated inputs, run the full case using the same batch, case-file suffix, and case name. The ordinary ReEDS workflow remains unchanged:

```text
conda activate reeds2
python runreeds.py -b no_renewable_growth -c seia -s <case-name>
```

Do not reuse an old case directory without checking its generated inputs. Case directories can contain stale files from prior runs.

## Validation checklist

### Input validation

- [ ] The custom runfiles file changes only the `techs_banned.csv` source path.
- [ ] The custom YAML uses only `st` and/or `county` scopes.
- [ ] The active technology list was derived from `techs_{techs_suffix}.csv`.
- [ ] The case uses `GSw_PVB=1` when existing PVB must remain modeled as hybrid PVB.
- [ ] PVB classes match `GSw_PVB_Types`.
- [ ] CSP classes are included when `GSw_CSP` is enabled.
- [ ] All model regions in the selected case are covered.
- [ ] `inputs_case/techs_banned.csv` exists and has the expected dimensions.

### Model-result validation

- [ ] Existing wind and solar capacity remains available.
- [ ] Existing PVB remains modeled as hybrid PVB rather than being split into standalone UPV and `battery_li`.
- [ ] Prescribed onshore and offshore wind builds remain present where intended.
- [ ] No unprescribed endogenous investments occur for wind-ons, wind-ofs, UPV, or PVB.
- [ ] No endogenous CSP investments occur when CSP is included in the counterfactual ban list.
- [ ] Distributed/rooftop PV follows its original exogenous trajectory.
- [ ] Any remaining renewable additions are identified as prescribed, mandated, or otherwise exogenous.

Because `tech_banned(i,r)` removes investment availability but does not necessarily remove every associated `valcap` entry, validate investment outputs—not only capacity-variable dimensions. Zero-valued or unused capacity entries may still be present in intermediate model structures.

## Important edge cases

### Prescribed offshore requirements

Offshore requirements or other policy prescriptions can intentionally create prescribed offshore builds. Those builds are exempted by the `valinv` logic and should be treated as exogenous additions, not as failures of the counterfactual.

### Distributed PV

The UPV ban does not affect distributed/rooftop PV. Distributed PV is supplied through an exogenous dGen input pathway. To remove that growth, a separate distributed-PV scenario or input customization is required.

### Refurbishments and upgrades

The counterfactual should distinguish new endogenous construction from refurbishments or technology upgrades. Inspect the reported investment categories used by the case before declaring the counterfactual successful.

### Partial regional coverage

A ban list that omits a state or model region leaves an opening for endogenous investment there. Always compare the generated `techs_banned.csv` columns against the case's `hierarchy.csv` and the active model-region set.

## Relevant implementation paths

- `reeds/input_processing/runfiles.csv`: identifies the source YAML for `techs_banned.csv`.
- `reeds/input_processing/copy_files.py`: converts the YAML into the case-level GAMS table.
- `reeds/core/setup/b_inputs.gms`: loads `tech_banned(i,r)` and applies it to `valinv`.
- `runreeds.py`: applies `file_replacements` before the generated input-processing script runs.
- `cases.csv`: documents `file_replacements`, `techs_suffix`, `GSw_PVB`, `GSw_PVB_Types`, `GSw_CSP`, and the siting switches.

## Transmission-permitting and transmission-buildout counterfactual

This section describes transmission controls that can be combined with the no-renewable-growth counterfactual. The focus is a complete halt to new bulk transmission expansion between the 54 model zones in the `z54` regional aggregation.

### 1. Delay when new transmission can begin

ReEDS provides timing controls for endogenous transmission expansion:

- `years_until_trans_nearterm`: number of years before near-term transmission expansion is allowed.
- `years_until_trans_longterm`: number of years before long-term transmission expansion is allowed.
- `GSw_TransInvNearTerm`: indicates whether transmission investment is allowed before the long-term expansion year.

The default scalar values are one year before near-term transmission expansion and eight years before long-term transmission expansion. The model disables most new transmission investment before the near-term start year. If near-term investment is disabled, the model keeps those investment routes unavailable until the long-term start year.

These controls are useful for representing permitting delays, construction lead times, or a temporary transmission-permitting moratorium. They do not by themselves impose a permanent national halt unless the timing horizon extends beyond all modeled years.

### 2. Limit annual national transmission deployment

ReEDS can limit annual transmission deployment using:

- `GSw_TransInvMaxNearTerm`
- `GSw_TransInvMaxLongTerm`
- `GSw_TransInvMaxTypes`

The annual limits are measured in terawatt-miles per year (TW-miles/year). The near-term and long-term limits can differ.

`GSw_TransInvMaxTypes` determines which investments count toward the annual limit:

- `0`: no annual transmission investment limit.
- `1`: interzonal transmission only.
- `2`: interzonal transmission and network reinforcement.
- `3`: interzonal transmission, network reinforcement, and spur lines.

A value of zero for `GSw_TransInvMaxNearTerm` or `GSw_TransInvMaxLongTerm` turns the corresponding constraint off; it does not impose a zero-build limit. Therefore, these switches should not be used alone to represent a complete halt to transmission construction.

The annual limit is based on transmission capacity investment multiplied by representative route distance. It is therefore a construction-throughput constraint rather than a simple megawatt cap.

### 3. Restrict expansion to selected geographic areas

`GSw_TransRestrict` specifies the spatial hierarchy within which new interzonal transmission expansion is allowed. Available hierarchy levels include:

- `r`: ReEDS model zone.
- `nercr`: North American Electric Reliability Corporation (NERC) region.
- `transreg`: transmission region.
- `transgrp`: transmission group.
- `cendiv`: census division.
- `st`: state.
- `interconnect`: asynchronous interconnection.
- `country`: country.
- `usda_region`: United States Department of Agriculture (USDA) region.

For example, setting `GSw_TransRestrict=st` allows expansion only when both endpoint zones are in the same state, thereby prohibiting interstate expansion. Setting `GSw_TransRestrict=interconnect` prohibits expansion across interconnection boundaries.

When `GSw_TransRestrict=r`, ReEDS removes all investment routes between model zones. Under a `z54` regional aggregation, this means that new bulk transmission expansion between the 54 ReEDS zones is not available to the optimization.

### 4. Cap transmission capacity on individual interfaces

ReEDS provides interface capacity caps through:

- `GSw_TransCapMaxEachType`
- `GSw_TransCapMaxAllTypes`
- `GSw_TransCapMaxTypes`

`GSw_TransCapMaxEachType` limits the total capacity of each transmission type on an individual balancing-area-to-balancing-area (BA-to-BA) interface. `GSw_TransCapMaxAllTypes` limits the combined capacity of selected transmission types on that interface.

`GSw_TransCapMaxTypes` selects the transmission types subject to those limits:

- `0`: no transmission types.
- `1`: all transmission types.
- `2`: voltage source converter (VSC) transmission.
- `3`: all direct-current (DC) transmission.

These switches are useful for representing hard limits on individual corridors or interfaces. They are not a custom corridor-list mechanism; applying different caps to selected interfaces would require additional input processing or model changes.

### 5. Control which candidate projects are available

Future transmission capacity is represented using candidate and planned transmission inputs. Candidate projects can be controlled through:

- project availability;
- project capacity;
- project online year;
- project certainty status;
- the `GSw_TransScen` transmission scenario switch.

For planned high-voltage direct-current (HVDC) projects, the relevant input fields include:

- `year_online`: earliest year in which the project can come online.
- `MW`: maximum project capacity.
- `certain=1`: the project is treated as a required or exogenous build at the specified capacity.
- `certain=0`: the project is optional and may be built up to the specified capacity.

A permitting scenario can therefore remove a candidate project, delay its `year_online`, reduce its permitted capacity, change a project from certain to possible, or exclude additional HVDC scenarios through `GSw_TransScen=none`.

The baseline planned HVDC projects and scenario-specific HVDC projects are loaded during transmission input processing. The model then constructs the future transmission capacity table from these inputs.

### 6. Make transmission economically harder to build

Economic controls can represent increased permitting, mitigation, siting, financing, or construction costs without imposing an absolute prohibition:

- `GSw_TransCostMult`: multiplier on bulk interzonal transmission capital costs.
- `GSw_TransIntraCost`: cost of intra-zone network reinforcement.
- `GSw_TransHurdleRate`: enables additional costs on interzonal electricity flows.
- `GSw_TransHurdleLevel1` and `GSw_TransHurdleLevel2`: identify the spatial hierarchy boundaries at which hurdle rates apply.

Hurdle rates affect the cost of operating over transmission and can reduce the value of long-distance power transfers. They do not directly prevent transmission construction. Similarly, a transmission capital-cost multiplier makes construction less attractive but does not impose a hard buildout limit.

### 7. Tighten aggregate interface flow limits

ReEDS can represent aggregate flow restrictions across groups of transmission interfaces using:

- `GSw_TransGroupContraint`: enables or disables grouped interface flow constraints.
- `GSw_TransGroupDerate`: derates the contribution of new interzonal alternating-current (AC) transmission to grouped transfer limits.

The default grouped-interface derate is 15 percent. Thus, 100 megawatts (MW) of new interzonal AC capacity contributes 85 MW to the grouped planning-subregion transfer limit.

These controls represent network-security and transfer-capability limitations rather than permitting restrictions. They can be useful when the practical limitation is that new lines cannot provide unlimited usable transfer capability across a constrained interface.

## Hard national halt to bulk transmission expansion

For the current `z54` scenario, the direct configuration for halting new bulk transmission expansion between the model zones is:

```text
GSw_ZoneSet = z54
GSw_TransRestrict = r
```

The `z54` zone set contains 54 aggregated ReEDS model zones. Counties assigned to the same `z54` zone are not represented as separate bulk-transmission network nodes.

`GSw_TransRestrict=r` sets the investment-route set to unavailable for all interzonal transmission routes. Consequently, new interzonal alternating-current (AC), line-commutated-converter (LCC) high-voltage direct-current (HVDC), and voltage source converter (VSC) HVDC investment is not available to the optimization.

Existing transmission capacity remains available. The restriction applies to new modeled transmission investment and does not remove the existing network.

The annual transmission investment limits are not required for this hard-halt case. In particular, setting an annual limit to zero should not be interpreted as a zero-build setting because zero disables the annual investment constraint.

## Caveats

### Model-zone versus county resolution

Under `GSw_ZoneSet=z54`, counties within a model zone are aggregated. ReEDS does not represent explicit county-to-county bulk transmission lines within that zone.

Therefore, the following interpretation is appropriate:

```text
GSw_ZoneSet = z54
GSw_TransRestrict = r
```

This means:

- no new bulk transmission between the 54 `z54` model zones;
- no explicit county-to-county bulk transmission network within each aggregated zone;
- existing interzonal transmission remains available;
- aggregate intra-zone interconnection and network-reinforcement representations may still apply to new generation.

If the intended policy is to prohibit new bulk transmission between individual counties, a county-level or otherwise finer spatial aggregation is required.

### Intra-zone point-of-interconnection capacity

ReEDS represents intra-zone point-of-interconnection (POI) capacity through an aggregate `INV_POI(r,t)` variable for each model zone. This is not a geographically explicit county-level transmission line.

`GSw_TransRestrict=r` does not itself disable this aggregate POI representation. Setting `GSw_TransIntraCost=0` turns off the POI requirement and associated cost, but it does not impose a physical no-POI-build constraint. It instead removes the explicit modeled requirement and cost.

### Spur lines

The `GSw_SpurScen` switch controls whether spur lines are modeled explicitly:

- `GSw_SpurScen=0`: spur-line costs remain embedded in resource supply curves, but explicit spur-line investment variables are not used.
- `GSw_SpurScen=1`: spur-line investment is modeled explicitly.

Setting `GSw_SpurScen=0` therefore suppresses explicit spur-line investment reporting but does not remove the associated embedded resource-cost treatment.

### Planned and certain transmission projects

Transmission project inputs distinguish possible projects from certain projects. A hard transmission restriction should be validated against the solved investment outputs because planned and certain projects are handled through the future transmission-capacity input pathway.

The expected validation result for the hard-halt case is zero new interzonal transmission investment in every modeled year. Existing transmission capacity should remain unchanged.

## Recommended setup

For the current no-renewable-growth scenario using the 54-zone regional aggregation, use:

```text
GSw_ZoneSet = z54
GSw_TransRestrict = r
```

Retain the base-case values for the other transmission switches unless the scenario has a separate assumption about intra-zone reinforcement or spur-line accounting.

The recommended interpretation is:

- halt all new bulk transmission expansion between the 54 model zones;
- retain existing transmission capacity;
- do not use zero annual limits as the halt mechanism;
- treat aggregate intra-zone POI capacity separately;
- treat explicit and embedded spur-line accounting separately;
- validate investment outputs rather than relying only on capacity-variable dimensions.

## Resolving policy conflicts with the hard halt

The hard halt can conflict with policy requirements that require new renewable
capacity. In particular, the base case enables state RPS/CES requirements
through `GSw_StateRPS=1`, and the default offshore-wind mandate file can require
new offshore wind capacity in states such as Connecticut, Rhode Island,
Virginia, and New York.

When endogenous wind and solar growth is disabled and new transmission
investment is also prohibited, those requirements can make the model
infeasible. The expected failure appears in `eq_RPS_OFSWind` when required
offshore-wind capacity exceeds existing offshore-wind capacity.

For the `USA_fast_no_re_2026` counterfactual, use:

```text
GSw_StateRPS = 0
```

This is the deliberate Option 2 configuration. It disables the state RPS/CES
requirement system for this counterfactual, including the offshore-wind
mandates that otherwise conflict with the no-growth and no-transmission-build
assumptions. It does not remove existing generation or existing transmission
capacity.

Option 1—retaining all state requirements and accepting infeasibility—is not
useful for the intended counterfactual. Option 3—removing only the
offshore-wind mandate file—could avoid the first conflict but would leave other
state policy requirements available to create later infeasibilities, so it is
not the selected configuration.

## State-cap constraints

`GSw_StateCap` controls annual state-level CO₂ cap-and-trade-style constraints.
The `eq_state_cap(st,t)` equation requires emissions attributed to a state to
remain at or below `state_cap(st,t)`. The attributed quantity includes:

1. In-state process CO₂ emissions.
2. Emissions attributed to electricity imported into that state.

For imported electricity, ReEDS uses the sending region's CO₂ emissions rate
from the previous solve year. With `GSw_StateCO2ImportLevel=interconnect`, that
sending-region rate is the previous year's interconnect-average rate broadcast
to each sending ReEDS region.

The active `state_cap.csv` input contains state-year caps for California,
Delaware, and New Jersey. `GSw_StateCap=0` disables all of those state-cap
constraints. It does not disable the separate RGGI or CSAPR mechanisms.

Disabling the state-cap system globally is consistent with treating the
counterfactual limitation as a national technology/transmission restriction and
avoiding a California-specific numerical adjustment. It is also more uniform
than relaxing only the California cap to make the model feasible. However, it is
still a substantive policy relaxation: it removes modeled state CO₂ compliance
requirements rather than only removing endogenous renewable growth. That
interpretation should be stated explicitly in the scenario description.

For `USA_fast_no_re_2026`, the selected permanent treatment is:

```text
GSw_StateCap = 0
```

## Restart-based feasibility diagnostics

A failed annual solve can be diagnosed without rerunning earlier years by using
the prior year's GAMS restart workfile. A file named `<case>_<year>i0.g00`
contains the model state immediately after that year's first solve iteration.
For example, the 2033 annual solve can be rerun by loading the solved 2032
workfile and updating the year-specific parameters for 2033.

Restart diagnostics use a copied or run-local override because the annual solve
script loads stored symbols from the workfile. Changing `cases_seia.csv` or
`inputs_case/gswitches.csv` after the restart was created does not change the
runtime state already stored in that restart file.

For the `USA_fast_no_re_2026` run, the 2033 conflict was concentrated in
California. The leading hypothesis is a California state CO₂ cap conflict
amplified by saturated, fixed transmission imports:

- The solved 2032 California cap expression was effectively binding at 35 MMT.
- The California cap falls to 33 MMT in 2033.
- California peak load rises between 2032 and 2033.
- Existing external interfaces into California were already near capacity.
- `GSw_TransRestrict=r` prevents new interzonal transmission investment.

The staged diagnostic files live only inside the run directory:

```text
<run_dir>/diagnostics/
<run_dir>/cleanup_2033_diagnostics.sh
```

They do not modify the repository source or permanent case inputs. The runner
temporarily replaces the run-local `inputs_case/diagnose.gms`, invokes the
existing annual solve script with the 2032 restart, and restores the original
file after the job exits.

The diagnostic variants are:

| Variant | Temporary override |
| --- | --- |
| `statecap0` | `Sw_StateCap = 0` |
| `statecap_hold` | `state_cap("CA","2033") = 35000000` |
| `transon` | Re-enables eligible 2033 `routes_inv` entries |
| `firmoff` | `Sw_PRM_NetImportLimit = 0` |
| `statecap0_transon` | State caps off plus transmission on |
| `all_relax` | All staged relaxations together |

Run only one diagnostic at a time. Each solve can use roughly 11 GB and may take
hours if it remains infeasible. A restart diagnostic skips the earlier solve
years and resource-adequacy iterations, but an infeasible or numerically
difficult variant can still take as long as the hardest single-year solve in a
full run. Running several such diagnostics sequentially can therefore approach
or exceed the wall-clock cost of a short scenario run.

Use a diagnostic-specific solver resource limit when a test does not need to run
to the default 48-hour CPLEX limit. For example, adding
`ReEDSmodel.resLim = 7200 ;` to a diagnostic snippet caps the solve at two
hours. A resource-limit stop is inconclusive: it means the test did not finish,
not that the model was proven infeasible.

### 2026-10-16 investigation status

The `statecap0` diagnostic completed successfully:

```text
**** SOLVER STATUS     1 Normal Completion
**** MODEL STATUS      1 Optimal
Objective: 1473312665972.406738
```

The 2033 solve took approximately 9 minutes with state caps disabled, compared
with the original 2033 solve that required approximately 8.4 hours before CPLEX
proved infeasibility. This confirms that the active state-cap system is
sufficient to cause the observed 2033 failure.

This result does not yet prove that California alone is the source of the
infeasibility, because `statecap0` disables every active state-cap constraint.
With `GSw_StateCap=0` selected as the permanent treatment, that distinction is
not required for the scenario to proceed.

The optional `statecap_hold` diagnostic was terminated after approximately
3 hours 36 minutes while still in a slow CPLEX dual-infeasibility phase. Its
result is therefore inconclusive: it did not prove feasibility or infeasibility.
The remaining `transon`, `firmoff`, `statecap0_transon`, and `all_relax`
diagnostics were tabled because they would not change the selected state-cap
treatment and could require comparable solve time.

The first `statecap0` wrapper reported `Exit 1` because the staged checker
script incorrectly appended a stray `}` to the diagnostic filename. The GAMS
solve itself was optimal, and the checker was corrected afterward.

After the solve, the runner restored the pre-diagnostic versions of:

- `inputs_case/diagnose.gms`
- `handoff/reeds_data/reeds_data_2033.gdx`
- `outputs/tc_phaseout_data/emit_for_tc_phaseout_calc_2033.gdx`

The diagnostic-specific outputs remain available for review:

- `lstfiles/<case>_2033_statecap0.lst`
- `g00files/<case>_2033_statecap0.g00`
- `diagnostics/gamslog_statecap0.txt`
- `diagnostics/statecap0.console.log`

Restoring those original artifacts does not prevent subsequent diagnostics. Each
runner invocation temporarily installs the requested diagnostic snippet and
backs up/restores the affected artifacts again.

### Run one diagnostic with `nohup`

From the run directory:

```bash
cd <run_dir>

nohup bash -c \
  './diagnostics/run_2033_diagnostic.sh statecap0; ./diagnostics/check_2033_diagnostic.sh statecap0' \
  > diagnostics/statecap0.console.log 2>&1 < /dev/null &

echo $! > diagnostics/statecap0.pid
```

The process continues after an SSH disconnect. To check whether it is still
running:

```bash
ps -p "$(cat diagnostics/statecap0.pid)" -o pid,etime,cmd
pgrep -af gams
```

To monitor progress:

```bash
tail -f diagnostics/statecap0.console.log
```

`Ctrl+C` stops `tail`; it does not stop the diagnostic.

For a structured status report, use:

```bash
./diagnostics/status_2033_diagnostic.sh statecap_hold
```

To refresh that report in the same terminal:

```bash
watch -n 60 './diagnostics/status_2033_diagnostic.sh statecap_hold'
```

The status report shows the wrapper process, the GAMS/CPLEX process tree,
elapsed runtime, memory use, recent iteration and infeasibility markers, and the
final model status when available. CPLEX does not provide a reliable completion
estimate; elapsed time and iteration progress are tracking aids, not an ETA.

Each diagnostic uses variant-specific files. When moving to the next variant,
replace `statecap0` in the runner argument, checker argument, console-log path,
and PID-file path. For example, `statecap_hold` uses:

```bash
nohup bash -c \
  './diagnostics/run_2033_diagnostic.sh statecap_hold; ./diagnostics/check_2033_diagnostic.sh statecap_hold' \
  > diagnostics/statecap_hold.console.log 2>&1 < /dev/null &

echo $! > diagnostics/statecap_hold.pid
```

Its live logs are:

```bash
tail -f diagnostics/statecap_hold.console.log
tail -f diagnostics/gamslog_statecap_hold.txt
```

The runner also writes variant-specific listing and restart files:

```text
lstfiles/<case>_2033_statecap_hold.lst
g00files/<case>_2033_statecap_hold.g00
```

Do not monitor or overwrite the `statecap0` logs when running another variant;
the prior diagnostic files remain available for comparison.

### Read the result

The checker prints the GAMS solve summary and the end of the diagnostic log:

```bash
./diagnostics/check_2033_diagnostic.sh statecap0
```

A feasible diagnostic has:

```text
**** SOLVER STATUS     1 Normal Completion
**** MODEL STATUS      1 Optimal
```

An unresolved conflict has an infeasible model status, such as:

```text
**** MODEL STATUS      19 Infeasible - No Solution
```

The diagnostic listing is named separately from the original failed run output:

```text
lstfiles/<case>_2033_statecap0.lst
```

Recommended diagnostic order:

1. `statecap0`: tests whether all state-cap constraints are sufficient to cause
   the failure.
2. `statecap_hold`: tests whether holding California's 2033 cap at the 2032
   level is sufficient to restore feasibility.
3. `transon`: tests whether the hard transmission halt is independently
   blocking feasibility.
4. `firmoff`: tests the firm net-import limit.
5. `statecap0_transon` and `all_relax`: combined tests used only if the
   single-variable tests remain infeasible.

The `transon` diagnostic is intentionally broad. Re-enabling `routes_inv` for
2033 permits transmission investment generally; it does not restrict the test to
prescribed or certain transmission projects.

### Clean up the diagnostic artifacts

Run cleanup only after preserving any diagnostic listings or logs that should
remain available:

```bash
cd <run_dir>
./cleanup_2033_diagnostics.sh
```

The cleanup script refuses to run while a 2033 diagnostic GAMS process is
active. It restores the original `inputs_case/diagnose.gms` and the 2033
handoff artifacts that existed before the diagnostic. It removes the diagnostic
GAMS snippets, console logs, GAMS logs, diagnostic listings, diagnostic restart
files, the known `225a` GAMS scratch directory, and the staging directory. It
does not remove the original failed-run listing or restart file.

## Validation checklist for the transmission restriction

- [ ] The case uses `GSw_ZoneSet=z54`.
- [ ] The case uses `GSw_TransRestrict=r`.
- [ ] The case uses `GSw_StateRPS=0`.
- [ ] The case uses `GSw_StateCap=0`.
- [ ] The generated case switches contain the intended values.
- [ ] New interzonal AC transmission investment is zero in all modeled years.
- [ ] New LCC HVDC transmission investment is zero in all modeled years.
- [ ] New VSC HVDC transmission investment is zero in all modeled years.
- [ ] Existing interzonal transmission capacity remains available.
- [ ] Any remaining transmission-related investment is identified as aggregate POI reinforcement, spur-line accounting, or another separate investment category.
- [ ] Planned or certain future transmission projects are checked explicitly.
- [ ] No conclusion is drawn from annual-limit values of zero, because zero disables the annual investment constraint.
