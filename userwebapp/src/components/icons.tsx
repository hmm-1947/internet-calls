import type { ReactNode, SVGProps } from "react";

type P = { size?: number } & SVGProps<SVGSVGElement>;

function mk(path: ReactNode, fill = false) {
  return function Icon({ size = 20, ...p }: P) {
    return (
      <svg
        width={size}
        height={size}
        viewBox="0 0 24 24"
        fill={fill ? "currentColor" : "none"}
        stroke={fill ? "none" : "currentColor"}
        strokeWidth={1.9}
        strokeLinecap="round"
        strokeLinejoin="round"
        {...p}
      >
        {path}
      </svg>
    );
  };
}

export const IconHome = mk(<path d="M3 11l9-8 9 8M5 10v10h14V10" />);
export const IconChat = mk(<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z" />);
export const IconPhone = mk(<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z" />);
export const IconSettings = mk(<><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" /></>);
export const IconCoin = mk(<><circle cx="12" cy="12" r="10" /><path d="M12 7v10M9.5 9.5h4a1.5 1.5 0 0 1 0 3h-3a1.5 1.5 0 0 0 0 3h4" strokeWidth={1.6} /></>);
export const IconVideo = mk(<><rect x="2" y="6" width="14" height="12" rx="2" /><path d="M22 8l-6 4 6 4z" /></>);
export const IconVideoOff = mk(<path d="M2 2l20 20M16 11.5V8l6-2v12l-3-1M10 6H4a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h10a2 2 0 0 0 1.5-.7" />);
export const IconMic = mk(<><rect x="9" y="2" width="6" height="12" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v4" /></>);
export const IconMicOff = mk(<path d="M2 2l20 20M9 9v2a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.9-.8M5 11a7 7 0 0 0 11.2 5.6M19 11a7 7 0 0 1-.6 2.8M12 18v4" />);
export const IconGift = mk(<><rect x="3" y="8" width="18" height="4" rx="1" /><path d="M12 8v13M5 12v9h14v-9M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5" /></>);
export const IconSend = mk(<path d="M22 2L11 13M22 2l-7 20-4-9-9-4z" />);
export const IconClose = mk(<path d="M18 6L6 18M6 6l12 12" />);
export const IconBack = mk(<path d="M15 18l-6-6 6-6" />);
export const IconChevron = mk(<path d="M9 18l6-6-6-6" />);
export const IconSearch = mk(<><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></>);
export const IconStar = mk(<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z" />, true);
export const IconCheck = mk(<path d="M20 6L9 17l-5-5" />);
export const IconCheckAll = mk(<path d="M17 6L7 17l-4-4M22 6L12 17" />);
export const IconPin = mk(<path d="M12 17v5M9 3h6l-1 7 3 3H7l3-3z" />);
export const IconArchive = mk(<><rect x="2" y="3" width="20" height="5" rx="1" /><path d="M4 8v12h16V8M10 12h4" /></>);
export const IconMute = mk(<path d="M11 5L6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6" />);
export const IconEdit = mk(<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" />);
export const IconTrash = mk(<path d="M3 6h18M8 6V4h8v2M6 6l1 15h10l1-15" />);
export const IconPlay = mk(<path d="M6 4l14 8-14 8z" />, true);
export const IconPause = mk(<><rect x="6" y="4" width="4" height="16" /><rect x="14" y="4" width="4" height="16" /></>, true);
export const IconMinimize = mk(<path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7" />);
export const IconLock = mk(<><rect x="4" y="11" width="16" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></>);
export const IconLogout = mk(<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />);
export const IconHeadset = mk(<><path d="M3 14v-2a9 9 0 0 1 18 0v2" /><rect x="2" y="14" width="5" height="7" rx="2" /><rect x="17" y="14" width="5" height="7" rx="2" /></>);
export const IconUser = mk(<><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></>);
export const IconShield = mk(<path d="M12 2l8 3v7c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V5z" />);
export const IconDoc = mk(<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M8 13h8M8 17h8" />);
export const IconPlus = mk(<path d="M12 5v14M5 12h14" />);
export const IconCamera = mk(<><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" /><circle cx="12" cy="13" r="4" /></>);
export const IconPhoneEnd = mk(<path d="M10.7 13.3a16 16 0 0 1-2.6-3.3L10 8.5 8.5 4H4.5A2 2 0 0 0 2.5 6a17 17 0 0 0 4.6 11.3M21 16v3a2 2 0 0 1-2 2M2 2l20 20" />);
export const IconEye = mk(<><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8S1 12 1 12z" /><circle cx="12" cy="12" r="3" /></>);
export const IconEyeOff = mk(<path d="M17.9 17.9A10.9 10.9 0 0 1 12 20C5 20 1 12 1 12a18.5 18.5 0 0 1 5.1-5.9M9.9 4.2A10.7 10.7 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.2 3.2M14.1 14.1a3 3 0 1 1-4.2-4.2M1 1l22 22" />);
export const IconMore = mk(<><circle cx="12" cy="5" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="12" cy="19" r="1" /></>, true);
export const IconWhatsapp = mk(<path d="M3 21l1.7-5A9 9 0 1 1 8 19.3z" />);
export const IconSpeaker = mk(<><path d="M11 5L6 9H3v6h3l5 4z" /><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13" /></>);
export const IconSpeakerOff = mk(<><path d="M11 5L6 9H3v6h3l5 4z" /><path d="M22 9l-6 6M16 9l6 6" /></>);
