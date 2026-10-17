import { useNavigate, useParams } from "react-router-dom";
import { ChatThread } from "../components/ChatThread";
import { ChatThreadList } from "../components/ChatThreadList";
import { Empty } from "../components/ui";
import { IconChat } from "../components/icons";
import { cx } from "../lib/util";

export default function Chats() {
  const { listenerId } = useParams();
  const nav = useNavigate();
  const id = listenerId ? Number(listenerId) : null;
  const valid = id !== null && Number.isFinite(id);

  return (
    <div className="flex h-full">
      <div className={cx("h-full w-full shrink-0 border-r border-line md:block md:w-[360px]", valid ? "hidden" : "block")}>
        <ChatThreadList activeId={valid ? id : null} onOpen={(l) => nav(`/chats/${l}`)} />
      </div>
      <div className={cx("h-full min-w-0 flex-1", valid ? "block" : "hidden md:block")}>
        {valid ? (
          <ChatThread key={id} listenerId={id!} onBack={() => nav("/chats")} />
        ) : (
          <div className="flex h-full items-center justify-center">
            <Empty icon={<IconChat size={56} />} title="Your messages" text="Select a chat to start talking." />
          </div>
        )}
      </div>
    </div>
  );
}
