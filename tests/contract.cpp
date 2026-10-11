#include "zml_plugin.h"
#include "patch.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <map>
namespace {
struct Route {ZmlLuaTransform fn;void* data;};
std::map<std::string,Route> routes;
std::string output;
int sinks{};
void check(bool condition,const char* label){if(!condition)throw std::runtime_error(label);}
void log(void*,const char*){}
int add(void*,const char* path,ZmlLuaTransform fn,void* data){check(routes.emplace(path,Route{fn,data}).second,"unique routes");return 1;}
void sink(void*,const char* p,size_t n){output.assign(p,n);++sinks;}
std::string read(const std::filesystem::path& p){std::ifstream f(p,std::ios::binary);check(bool(f),"read fixture");return {std::istreambuf_iterator<char>(f),{}};}
constexpr std::string_view battle=R"(local uiCtrl = require_ex('UI/Panels/Base/UICtrl')
BattleActionCtrl = HL.Class('BattleActionCtrl', uiCtrl.UICtrl)
BattleActionCtrl.OnShow = HL.Override() << function(self)
nativeShow(self)
end
BattleActionCtrl.OnHide = HL.Override() << function(self)
nativeHide(self)
end
BattleActionCtrl.OnClose = HL.Override() << function(self)
nativeClose(self)
end
HL.Commit(BattleActionCtrl)
)";
constexpr std::string_view camera=R"(local uiCtrl = require_ex('UI/Panels/Base/UICtrl')
LevelCameraCtrl = HL.Class('LevelCameraCtrl', uiCtrl.UICtrl)
LevelCameraCtrl._MoveCamera = HL.Method(HL.Userdata) << function(self, delta)
nativeMove(self,delta)
end
LevelCameraCtrl.ZoomCamera = HL.Method(HL.Number) << function(self, delta)
nativeZoom(self,delta)
end
HL.Commit(LevelCameraCtrl)
)";
}
int main(int argc,char** argv){try {
    check(argc==2 || argc==4,"usage");
    auto path=std::filesystem::absolute(argv[1]);auto dll=LoadLibraryW(path.c_str());check(dll!=nullptr,"actual DLL loads");
    auto entry=reinterpret_cast<ZmlPluginEntry>(GetProcAddress(dll,"ZML_PluginV1"));check(entry!=nullptr,"ABI1 exported");
    auto plugin=entry();check(plugin && plugin->size==sizeof(ZmlPlugin) && plugin->abi==1 && std::string_view(plugin->id)=="first-person-remix","identity");
    auto dir=path.parent_path().u8string();
    ZmlHost host{sizeof(ZmlHost),1,nullptr,reinterpret_cast<const char*>(dir.c_str()),"",log,add};
    check(!plugin->start(nullptr),"null host rejected");
    auto bad=host;bad.abi=2;check(!plugin->start(&bad),"ABI mismatch rejected");
    bad=host;bad.transform_lua=nullptr;check(!plugin->start(&bad),"missing host API rejected");
    bad=host;bad.mod_directory="C:/nonexistent-zml-firstperson-fixture";check(!plugin->start(&bad),"missing helpers rejected");
    check(plugin->start(&host)==1 && routes.size()==2,"two registered module routes");
    for(auto [module,source]:{std::pair{"UI/Panels/BattleAction/BattleActionCtrl",battle},std::pair{"UI/Panels/LevelCamera/LevelCameraCtrl",camera}}) {
        auto r=routes.at(module);sinks=0;output.clear();
        check(r.fn(r.data,source.data(),source.size(),sink,nullptr)==1 && sinks==1,"one atomic sink");
        check(output.find("native")!=output.npos && firstperson::count(output,"-- ZML_FIRST_PERSON_V1")==1,"original body preserved");
        auto patched=output;sinks=0;output="untouched";
        check(!r.fn(r.data,patched.data(),patched.size(),sink,nullptr) && !sinks && output=="untouched","idempotent no output");
        for(auto malformed:{std::string(source)+std::string(source),std::string("unexpected client"),std::string(source)+std::string(1,'\0')}) {
            sinks=0;check(!r.fn(r.data,malformed.data(),malformed.size(),sink,nullptr) && !sinks,"ambiguous/missing/NUL rejected");
        }
        check(!r.fn(r.data,nullptr,0,sink,nullptr),"null input");
        if(argc==4) {
            auto root=std::filesystem::path(argv[2]);auto out=std::filesystem::path(argv[3]);
            bool cam=std::string_view(module).find("LevelCamera")!=std::string_view::npos;
            auto relative=cam?L"ui/panels/levelcamera/levelcameractrl.lua":L"ui/panels/battleaction/battleactionctrl.lua";
            auto actual=read(root/relative);sinks=0;
            check(r.fn(r.data,actual.data(),actual.size(),sink,nullptr)==1 && sinks==1,"fresh real client source contract");
            std::filesystem::create_directories(out);
            std::ofstream(out/(cam?L"camera.lua":L"battle.lua"),std::ios::binary)<<output;
        }
    }
    std::string unchanged="sentinel";
    check(!firstperson::patch(battle,"",false,unchanged) && unchanged=="sentinel","empty helper atomic fail");
    check(!firstperson::patch(battle,std::string(97*1024,'x'),false,unchanged),"helper bounds");
    FreeLibrary(dll);std::cout<<"PASS ABI, atomic transforms, lifecycle contracts, compatibility guards\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
