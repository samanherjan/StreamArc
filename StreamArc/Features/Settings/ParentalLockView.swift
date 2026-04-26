import SwiftUI

struct ParentalLockView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var error: String?

    private var isEnabled: Bool {
        get { appEnv.settingsStore.parentalLockEnabled }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Parental Lock", isOn: Binding(
                        get: { appEnv.settingsStore.parentalLockEnabled },
                        set: { appEnv.settingsStore.parentalLockEnabled = $0 }
                    ))
                    .tint(Color.saAccent)
                }

                if appEnv.settingsStore.parentalLockEnabled {
                    Section("Set PIN") {
                        SecureField("4-digit PIN", text: $pin)
                            .keyboardType(.numberPad)
                        SecureField("Confirm PIN", text: $confirmPin)
                            .keyboardType(.numberPad)
                    }

                    if let error {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    Section {
                        Button("Save PIN") { savePIN() }
                            .tint(Color.saAccent)
                            .disabled(pin.isEmpty)
                    }
                }

                Section {
                    Text("When enabled, explicit content categories are hidden unless the PIN is entered.")
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.saBackground)
            .navigationTitle("Parental Lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func savePIN() {
        guard pin.count == 4 else {
            error = "PIN must be exactly 4 digits."
            return
        }
        guard pin == confirmPin else {
            error = "PINs do not match."
            return
        }
        guard pin.allSatisfy(\.isNumber) else {
            error = "PIN must contain digits only."
            return
        }
        appEnv.settingsStore.parentalPIN = pin
        error = nil
        dismiss()
    }
}
