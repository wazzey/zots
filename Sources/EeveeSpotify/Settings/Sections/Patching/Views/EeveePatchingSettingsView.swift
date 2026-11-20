import SwiftUI
import UIKit

struct EeveePatchingSettingsView: View {
    @State var patchType = UserDefaults.patchType
    @State var overwriteConfiguration = UserDefaults.overwriteConfiguration
    @State var trueShuffleEnabled = UserDefaults.trueShuffleEnabled
    @State var shufflePlusEnabled = UserDefaults.shufflePlusEnabled

    var body: some View {
        List {
            Section(
                footer: patchType == .disabled
                    ? nil
                    : Text(
                        "patching_description"
                            .localizeWithFormat("restart_is_required_description".localized)
                    )
            ) {
                Toggle(
                    "do_not_patch_premium".localized,
                    isOn: Binding<Bool>(
                        get: { patchType == .disabled },
                        set: { patchType = $0 ? .disabled : .requests }
                    )
                )
            }
            
            .onChange(of: patchType) { newPatchType in
                UserDefaults.patchType = newPatchType
                OfflineHelper.resetData()
            }
            
            .onChange(of: overwriteConfiguration) { overwriteConfiguration in
                UserDefaults.overwriteConfiguration = overwriteConfiguration
                OfflineHelper.resetData()
            }

            .onChange(of: trueShuffleEnabled) { isEnabled in
                UserDefaults.trueShuffleEnabled = isEnabled
            }

            .onChange(of: shufflePlusEnabled) { isEnabled in
                UserDefaults.shufflePlusEnabled = isEnabled
            }

            if patchType == .requests {
                Section(
                    footer: Text("overwrite_configuration_description".localized)
                ) {
                    Toggle(
                        "overwrite_configuration".localized,
                        isOn: $overwriteConfiguration
                    )
                }

                Section(
                    footer: Text(
                        "true_shuffle_dec".localized
                        + "restart_is_required_description".localized
                    )
                ) {
                    Toggle("true_shuffle".localized, isOn: $trueShuffleEnabled)
                }
            }

            Section(
                footer: Text(
                    "shuffle_plus_desc".localized
                    + "restart_is_required_description".localized
                )
            ) {
                Toggle("shuffle_plus".localized, isOn: $shufflePlusEnabled)
            }

            SpacerView()
        }
        .eeveeSettingsStyle()
        .animation(.default, value: patchType)
    }
}
