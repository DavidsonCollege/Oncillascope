#if canImport(CoreWLAN)
import CoreWLAN
import WiFiModel

/// Translators from CoreWLAN enums to our framework-independent model types.
enum CWMappers {

    static func band(_ b: CWChannelBand) -> Band {
        switch b {
        case .band2GHz: return .ghz2_4
        case .band5GHz: return .ghz5
        case .band6GHz: return .ghz6
        default: return .unknown
        }
    }

    static func width(_ w: CWChannelWidth) -> ChannelWidth {
        switch w {
        case .width20MHz: return .mhz20
        case .width40MHz: return .mhz40
        case .width80MHz: return .mhz80
        case .width160MHz: return .mhz160
        default: return .unknown
        }
    }

    static func channel(_ ch: CWChannel?) -> ChannelInfo {
        guard let ch else { return ChannelInfo(number: 0) }
        return ChannelInfo(number: ch.channelNumber,
                           width: width(ch.channelWidth),
                           band: band(ch.channelBand))
    }

    /// CWPHYMode tops out at 11ac on every shipping SDK; ax/be are inferred from IEs or
    /// `wdutil` instead. This maps what CoreWLAN can report.
    static func phyMode(_ mode: CWPHYMode) -> PHYGeneration {
        switch mode {
        case .mode11a: return .legacy11a
        case .mode11b: return .legacy11b
        case .mode11g: return .legacy11g
        case .mode11n: return .n
        case .mode11ac: return .ac
        default: return .unknown
        }
    }

    static func security(_ s: CWSecurity) -> SecurityMode {
        switch s {
        case .none: return .open
        case .WEP, .dynamicWEP: return .wep
        case .wpaPersonal, .wpaPersonalMixed: return .wpaPersonal
        case .wpaEnterprise, .wpaEnterpriseMixed: return .wpaEnterprise
        case .wpa2Personal: return .wpa2Personal
        case .wpa2Enterprise: return .wpa2Enterprise
        case .wpa3Personal: return .wpa3Personal
        case .wpa3Enterprise: return .wpa3Enterprise
        case .wpa3Transition: return .wpa2wpa3Personal
        case .OWE, .oweTransition: return .enhancedOpen
        case .personal: return .wpa2Personal
        case .enterprise: return .wpa2Enterprise
        default: return .unknown
        }
    }

    /// Derive a `CWNetwork`'s security by probing `supportsSecurity(_:)`, newest-first.
    static func networkSecurity(_ net: CWNetwork) -> SecurityMode {
        let ordered: [(CWSecurity, SecurityMode)] = [
            (.wpa3Enterprise, .wpa3Enterprise),
            (.wpa3Personal, .wpa3Personal),
            (.wpa3Transition, .wpa2wpa3Personal),
            (.wpa2Enterprise, .wpa2Enterprise),
            (.wpa2Personal, .wpa2Personal),
            (.wpaEnterprise, .wpaEnterprise),
            (.wpaPersonal, .wpaPersonal),
            (.OWE, .enhancedOpen),
            (.WEP, .wep),
            (.none, .open),
        ]
        for (cw, mode) in ordered where net.supportsSecurity(cw) {
            return mode
        }
        return .unknown
    }
}
#endif
