// 0.1.0 performance pass: installs Godot's WorkerThreadPool as the follower's parallel-for
// (NavigationService::parallel_for, navigation_jobs.h). Only the GDExtension build compiles this
// file; the standalone navigation tests leave parallel_for empty and step serially.
#include "navigation_jobs.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/variant/string.hpp>

namespace {

void run_on_pool(void (*job)(void *, uint32_t), void *data, uint32_t count) {
	godot::WorkerThreadPool *pool = godot::WorkerThreadPool::get_singleton();
	if (pool == nullptr || count < 2) {
		for (uint32_t i = 0; i < count; ++i) {
			job(data, i);
		}
		return;
	}
	// High priority, like the pose solve: the physics tick waits for it.
	const godot::WorkerThreadPool::GroupID group =
			pool->add_native_group_task(job, data, int(count), -1, true, godot::String("Pony follow step"));
	pool->wait_for_group_task_completion(group);
}

struct InstallParallelFollow {
	InstallParallelFollow() {
		ponynav::NavigationService::parallel_for = &run_on_pool;
	}
};

InstallParallelFollow install_parallel_follow;

} // namespace
