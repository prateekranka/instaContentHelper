# Pocket native UI checks

The native Creator app uses the Pocket design with monochrome chrome. These tests use TesterArmy e2e and the native mobile engine. They do not use an AI test provider or a live generation service.

## Run

1. Install the locked Node dependencies with `npm ci`.
2. Build the CreatorContentOS Debug scheme with assets included.
3. Select an idle, already-booted iPhone simulator. Set `POCKET_E2E_DEVICE` to its exact UDID.
4. Run the workspace, disk, and simulator preflight helpers before build or device work.
5. Install the build through e2e:

```sh
POCKET_E2E_INSTALL=1 POCKET_E2E_APP=/absolute/path/ContentHelper.app npx e2e run --grep 'Pocket opens'
```

6. Run a scenario with a fresh fixture session:

```sh
POCKET_E2E_SCENARIO=ready POCKET_E2E_SESSION=pocket-review-001 npx e2e run
```

The default device is the iPhone 18 Pro used for this task. The default build and report paths point to this task's durable evidence directory. Use `POCKET_E2E_APP` and `POCKET_E2E_OUTPUT` to select other paths.

## Scenarios

| Scenario | Coverage |
|---|---|
| ready | Optional onboarding, first idea, twelve shot navigation transitions, repeated completion, script cancel/save, caption save, clipboard, posted/undo/repost, relaunch persistence, one archive row |
| onboarding | Repeated starting-point and interest selections, Show my first idea, useful Today destination |
| retry | First generation fails once; Retry succeeds |
| slow | Slow generation, disabled duplicate submission, Today handoff |
| plan | Seven dates, Creator Voice setup/save, future generation/save, package tabs, cancelled and confirmed overwrite, replacement title persistence |
| alternatives | Partial shot progress after relaunch, backup preview/cancel, backup confirmation, Plan tomorrow |
| large | Accessibility Dynamic Type override, fixed actions, filming, Plan, You |
| long | Long-content fixture after onboarding, wrapping and navigation |
| motion | App-level Reduce Motion override and normal outcomes |
| empty | Empty Today, Plan generation, Make ready for Today, and filming handoff |
| welcome | Native welcome and Apple sign-in control; no real account sign-in |
| sync-error | A failed decision sync preserves local completion and visible feedback |

Every creator journey starts from optional onboarding. The empty and signed-out checks deliberately start at those states. Test data is isolated by `MCO_QA_SESSION`. Tests do not erase the simulator, clear its keychain, or use production creator data.

## Interpretation

- A passing build proves compilation only.
- A passing e2e report proves the recorded simulator scenario.
- Dynamic Type and Reduce Motion stress flags apply inside the app. They do not prove system Settings automation.
- Real Apple authentication, live model output, external publication, and physical iPhone behavior require separate proof.
- Native recordings and screenshots are stored beside each e2e report. Installation runs omit video because the mobile engine must first bind the exact device.
- Text edit checks use `pressSequentially` and the app's keyboard Done control. Native bulk fill left a leading character in this runner version. The tests verify the resulting text exactly after save and relaunch.
- The native tree can expose tab-bar items as tabs or buttons. Tests select the exact name inside the observed tab bar.
- Scroll checks measure the floating tab bar and filming controls. Native accessibility visibility alone can include obscured content.
- The nested backup sheet's Cancel and confirmation controls use fresh e2e geometry because the runner incorrectly reported overlap. The test then checks that the preview closes and the main idea is preserved.

Review status: `NOT_ADVISOR_APPROVED`. The user explicitly allowed best-effort Advisor review for this task.
