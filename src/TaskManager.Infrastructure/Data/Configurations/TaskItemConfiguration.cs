using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using TaskManager.Domain.Entities;

namespace TaskManager.Infrastructure.Data.Configurations;

/// <summary>
/// EF Core configuration for the TaskItem entity.
/// </summary>
public class TaskItemConfiguration : IEntityTypeConfiguration<TaskItem>
{
    /// <inheritdoc/>
    public void Configure(EntityTypeBuilder<TaskItem> builder)
    {
        builder.ToTable("tasks");

        builder.HasKey(t => t.Id);

        builder.Property(t => t.Id)
            .HasColumnName("id");

        builder.Property(t => t.Title)
            .HasColumnName("title")
            .HasMaxLength(300)
            .IsRequired();

        builder.Property(t => t.Description)
            .HasColumnName("description");

        builder.Property(t => t.Status)
            .HasColumnName("status")
            .IsRequired();

        builder.Property(t => t.Priority)
            .HasColumnName("priority")
            .IsRequired();

        builder.Property(t => t.DueDate)
            .HasColumnName("due_date");

        builder.Property(t => t.UserId)
            .HasColumnName("user_id")
            .IsRequired();

        builder.Property(t => t.ProjectId)
            .HasColumnName("project_id");

        builder.Property(t => t.CreatedAt)
            .HasColumnName("created_at")
            .IsRequired();

        builder.Property(t => t.UpdatedAt)
            .HasColumnName("updated_at")
            .IsRequired();

        // Indexes are created by Liquibase changesets (docker/liquibase); they are declared here to keep the model in sync.
        builder.HasIndex(t => new { t.UserId, t.CreatedAt })
            .IsDescending(false, true)
            .HasDatabaseName("idx_tasks_user_id_created_at");
        builder.HasIndex(t => new { t.CreatedAt, t.DueDate })
            .IsDescending(true, false)
            .HasDatabaseName("idx_tasks_created_at_due_date");
        builder.HasIndex(t => t.ProjectId);
        builder.HasIndex(t => t.Status);
        builder.HasIndex(t => t.Priority);
        builder.HasIndex(t => t.DueDate);

        builder.HasMany(t => t.TaskTags)
            .WithOne(tt => tt.Task)
            .HasForeignKey(tt => tt.TaskId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
