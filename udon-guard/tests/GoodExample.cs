// udon-guard 自测夹具：合规的 UdonSharp 写法。
// 预期：不产生任何 BLOCKED / ERROR。
// 注意：注释里提到 List<T> / async / try-catch 是故意的——
// 校验器应当"打码"注释，不把注释里的关键字当成违规。
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;

public class GoodExample : UdonSharpBehaviour
{
    [UdonSynced] private int counter;

    // 不要用 List<T>、async、try-catch、LINQ —— 这些在 Udon 里都不可用。
    private string note = "avoid List<T>, async and try-catch here";

    private void Start()
    {
        RequestSerialization();
    }

    public override void Interact()
    {
        if (!Networking.IsOwner(gameObject))
        {
            Networking.SetOwner(Networking.LocalPlayer, gameObject);
        }
        counter++;
        RequestSerialization();
    }

    private void SafeDelayed()
    {
        SendCustomEventDelayedSeconds(nameof(Interact), 1.0f);
    }
}
