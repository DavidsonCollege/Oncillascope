import Foundation

/// Human-readable names for 802.11 element IDs and Extension element IDs.
enum ElementNames {
    static func name(id: Int, extID: Int?) -> String {
        if id == 255, let extID {
            return extensionName(extID)
        }
        switch id {
        case 0: return "SSID"
        case 1: return "Supported Rates"
        case 3: return "DS Parameter Set"
        case 5: return "TIM"
        case 7: return "Country"
        case 11: return "BSS Load"
        case 32: return "Power Constraint"
        case 33: return "Power Capability"
        case 35: return "TPC Report"
        case 36: return "Supported Channels"
        case 37: return "Channel Switch Announcement"
        case 42: return "ERP Information"
        case 45: return "HT Capabilities"
        case 46: return "QoS Capability"
        case 48: return "RSN (Security)"
        case 50: return "Extended Supported Rates"
        case 54: return "Mobility Domain (802.11r)"
        case 59: return "Supported Operating Classes"
        case 61: return "HT Operation"
        case 62: return "Secondary Channel Offset"
        case 70: return "RM Enabled Capabilities (802.11k)"
        case 71: return "Multiple BSSID"
        case 74: return "Overlapping BSS Scan Parameters"
        case 107: return "Interworking"
        case 108: return "Advertisement Protocol"
        case 111: return "Roaming Consortium"
        case 113: return "Mesh Configuration"
        case 114: return "Mesh ID"
        case 127: return "Extended Capabilities"
        case 191: return "VHT Capabilities"
        case 192: return "VHT Operation"
        case 193: return "Extended BSS Load"
        case 195: return "VHT Transmit Power Envelope"
        case 197: return "Antenna Sector ID Pattern"
        case 201: return "Reduced Neighbor Report"
        case 221: return "Vendor Specific"
        case 255: return "Element Extension"
        default: return "Element \(id)"
        }
    }

    static func extensionName(_ extID: Int) -> String {
        switch extID {
        case 35: return "HE Capabilities"
        case 36: return "HE Operation"
        case 37: return "UORA Parameter Set"
        case 38: return "MU EDCA Parameter Set"
        case 39: return "Spatial Reuse Parameter Set"
        case 55: return "Multi-Link (802.11be)"
        case 59: return "HE 6 GHz Band Capabilities"
        case 106: return "EHT Operation"
        case 107: return "Multi-Link"
        case 108: return "EHT Capabilities"
        case 110: return "TID-to-Link Mapping"
        default: return "Extension Element \(extID)"
        }
    }
}
